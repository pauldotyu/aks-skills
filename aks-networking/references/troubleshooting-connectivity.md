# Troubleshooting Connectivity

Always start troubleshooting from **inside the cluster** before escalating to Azure-level diagnostics. Most networking issues originate from misconfigurations in Kubernetes resources.

## Step 1: Check pod health and readiness

Before investigating networking, confirm the target pods are running and ready:

```bash
# Check pod status and readiness
kubectl get pods -n <namespace> -o wide

# Look for pods that aren't Running/Ready
kubectl get pods -n <namespace> --field-selector='status.phase!=Running,status.phase!=Succeeded'

# Describe a specific pod for events, conditions, and container status
kubectl describe pod <pod-name> -n <namespace>

# Verify the application is actually listening on the expected port
kubectl exec <pod-name> -n <namespace> -- ss -tlnp
# Or for containers without ss:
kubectl exec <pod-name> -n <namespace> -- netstat -tlnp
```

If pods are not Ready, the service will not route traffic to them. Fix pod health first.

## Step 2: Verify services and endpoints

Service misconfigurations are the most common cause of connectivity failures.

```bash
# Check the service exists and has the correct type, ports, and selector
kubectl get service <service-name> -n <namespace> -o wide
kubectl describe service <service-name> -n <namespace>

# Check endpoints — these show which pod IPs the service routes to
kubectl get endpoints <service-name> -n <namespace>

# If using EndpointSlices (K8s 1.21+)
kubectl get endpointslices -n <namespace> -l kubernetes.io/service-name=<service-name>
```

**If endpoints are empty**, the service selector does not match any running/ready pod labels:

```bash
# Compare service selector to pod labels
kubectl get service <service-name> -n <namespace> -o jsonpath='{.spec.selector}'
kubectl get pods -n <namespace> --show-labels

# Verify target port matches what the container exposes
kubectl get service <service-name> -n <namespace> -o jsonpath='{.spec.ports[*]}'
```

## Step 3: Check network policies (including CiliumNetworkPolicy)

Network policies can silently block traffic. Check policies **before** running connectivity tests — if a deny policy is in place, the tests will fail and you'll waste time diagnosing the wrong thing. On AKS clusters with Cilium, **both** standard `NetworkPolicy` and `CiliumNetworkPolicy` / `CiliumClusterwideNetworkPolicy` are enforced simultaneously.

```bash
# List standard Kubernetes network policies in the namespace
kubectl get networkpolicies -n <namespace>

# Describe each policy to understand ingress/egress rules
kubectl describe networkpolicy <policy-name> -n <namespace>

# Check if a default-deny policy exists
kubectl get networkpolicies -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}: podSelector={.spec.podSelector}, policyTypes={.spec.policyTypes}{"\n"}{end}'

# List CiliumNetworkPolicies (if cluster uses Cilium dataplane)
kubectl get ciliumnetworkpolicies -n <namespace>
kubectl describe ciliumnetworkpolicy <policy-name> -n <namespace>

# List cluster-wide Cilium policies (no namespace)
kubectl get ciliumclusterwidenetworkpolicies
kubectl describe ciliumclusterwidenetworkpolicy <policy-name>

# Check Cilium endpoint status for a pod (shows which policies are applied)
kubectl get ciliumendpoints -n <namespace>
kubectl describe ciliumendpoint <pod-name> -n <namespace>
```

Common network policy issues:

- A `default-deny-ingress` policy exists but no policy allows traffic from the source
- Egress policies block the source pod from reaching the target
- Namespace selectors don't match because namespace labels are missing
- Port numbers in the policy don't match the actual container port
- A `CiliumNetworkPolicy` or `CiliumClusterwideNetworkPolicy` is blocking traffic even though standard `NetworkPolicy` allows it (both are enforced)
- Cilium DNS-based egress policy blocks FQDN resolution because DNS egress to CoreDNS is not explicitly allowed

```bash
# Verify namespace labels (required for namespaceSelector rules)
kubectl get namespace <namespace> --show-labels

# Add a label to a namespace if missing
kubectl label namespace <namespace> <key>=<value>

# Check Cilium agent health (if using Cilium)
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl exec -n kube-system <cilium-agent-pod> -- cilium status
kubectl exec -n kube-system <cilium-agent-pod> -- cilium policy get
```

Use `networkpolicy-viewer` or similar tools for visualizing policies across the cluster. For Cilium, use `cilium monitor` on the agent pod to observe real-time policy verdicts and drops.

## Step 4: Test in-cluster connectivity

Use a debug pod to test connectivity from within the cluster:

```bash
kubectl run netshoot --image=nicolaka/netshoot --rm -it -- bash
```

From inside the debug pod:

```bash
# Test service DNS resolution
nslookup <service-name>.<namespace>.svc.cluster.local

# Test connectivity to the service ClusterIP
curl -v http://<service-name>.<namespace>.svc.cluster.local:<port>

# Test direct pod-to-pod connectivity
curl -v http://<pod-ip>:<container-port>
ping <pod-ip>

# Trace the route to the target pod
traceroute <pod-ip>

# Test connectivity to external endpoints
curl -v https://example.com
nslookup example.com
```

If pod-to-pod works but service access fails, the issue is in the service/endpoint configuration.
If neither works, the network policy check in Step 3 should have revealed the cause — revisit those findings or investigate CNI issues.

## Step 5: Diagnose DNS issues

```bash
# Check CoreDNS pods are running
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide

# Check CoreDNS logs for errors
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Test DNS from a debug pod
kubectl run dnstest --image=busybox:1.28 --rm -it -- sh
# Inside:
# nslookup kubernetes.default
# nslookup <service-name>.<namespace>.svc.cluster.local
# nslookup <external-hostname>

# Check resolv.conf in a pod to verify DNS config
kubectl exec <pod-name> -n <namespace> -- cat /etc/resolv.conf
```

If internal DNS fails but external works, CoreDNS may be misconfigured. If both fail, check CoreDNS pod health and network policies affecting `kube-system`.

## Step 6: Debug ingress issues

When external traffic isn't reaching your service through an ingress:

```bash
# Check ingress resource configuration
kubectl get ingress -n <namespace>
kubectl describe ingress <ingress-name> -n <namespace>

# Verify the ingress controller pods are running
kubectl get pods -n ingress-nginx  # for NGINX
kubectl get pods -n kube-system -l app=ingress-appgw  # for AGIC

# Check ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50

# Verify the backend service is listed in the ingress
kubectl get ingress <ingress-name> -n <namespace> -o jsonpath='{.spec.rules[*].http.paths[*].backend}'

# Confirm the service the ingress points to has healthy endpoints
kubectl get endpoints <backend-service-name> -n <namespace>
```

## Step 7: Check kube-proxy and CNI health

```bash
# Check kube-proxy pods (handles service-to-pod routing via iptables/IPVS)
kubectl get pods -n kube-system -l component=kube-proxy
kubectl logs -n kube-system -l component=kube-proxy --tail=30

# Check CNI plugin pods
kubectl get pods -n kube-system | grep -E 'azure-cni|cilium|calico'

# On a node, check iptables NAT rules for a service (via node debug)
kubectl debug node/<node-name> -it --image=nicolaka/netshoot -- chroot /host iptables -t nat -L KUBE-SERVICES | grep <service-name>
```

## Step 8: Escalate to Azure-level diagnostics

Only after ruling out in-cluster issues, check Azure networking resources:

```bash
# Check the load balancer status and rules
az network lb show --resource-group <node-resource-group> --name kubernetes -o table
az network lb rule list --resource-group <node-resource-group> --lb-name kubernetes -o table

# Check NSG rules that may block traffic
az network nsg list --resource-group <node-resource-group> -o table
az network nsg rule list --resource-group <node-resource-group> --nsg-name <nsg-name> -o table

# Check effective routes on the node subnet
az network nic show-effective-route-table --resource-group <node-resource-group> --name <nic-name> -o table

# Check effective NSG rules on a node NIC
az network nic list-effective-nsg --resource-group <node-resource-group> --name <nic-name>

# Verify the subnet has available IPs (for Azure CNI)
az network vnet subnet show --resource-group <resource-group> --vnet-name <vnet-name> --name <subnet-name> --query '{addressPrefix:addressPrefix, availableIPs:delegations}'

# Check for Azure connectivity issues using AKS diagnostics
az aks kollect \
  --resource-group <resource-group> \
  --name <cluster-name>
```
