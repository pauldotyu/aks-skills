---
name: aks-networking
description: Configure and troubleshoot Azure Kubernetes Service (AKS) networking. Use when setting up or modifying CNI plugins (Azure CNI, kubenet, Azure CNI Overlay), configuring ingress controllers (NGINX, Application Gateway Ingress Controller), setting up internal or external load balancers, managing network policies, configuring DNS, or diagnosing connectivity issues between pods, services, or external endpoints.
license: MIT
metadata:
  author: pauldotyu
  version: "1.0"
compatibility: Requires kubectl connected to the target cluster and az CLI with an authenticated Azure session
---

# AKS Networking

This skill covers AKS networking configuration and troubleshooting, including CNI plugins, load balancers, ingress, network policies, and DNS.

## Network Plugin Options

### Azure CNI (recommended for production)

Pods get IPs from the VNet subnet. Required for Windows node pools and advanced networking features.

```bash
az aks create \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --network-plugin azure \
  --vnet-subnet-id <subnet-id> \
  --service-cidr 10.0.0.0/16 \
  --dns-service-ip 10.0.0.10
```

### Azure CNI Overlay (best for large clusters)

Pods get IPs from an overlay network, not the VNet. Reduces VNet IP consumption significantly.

```bash
az aks create \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --pod-cidr 192.168.0.0/16
```

### kubenet (simple but limited)

Pods use a private IP range with NAT. Does not support Windows nodes or some advanced features.

```bash
az aks create \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --network-plugin kubenet \
  --pod-cidr 10.244.0.0/16
```

## Load Balancers

### Public load balancer (default)

A Standard SKU public load balancer is created automatically when you expose a service of type `LoadBalancer`.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

### Internal load balancer

Use this for services that should only be reachable within the VNet.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-internal-service
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

### Static public IP for a load balancer

```bash
# Create a static IP in the node resource group
NODE_RG=$(az aks show \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --query "nodeResourceGroup" -o tsv)

az network public-ip create \
  --resource-group "$NODE_RG" \
  --name my-static-ip \
  --sku Standard \
  --allocation-method static
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: "<node-resource-group>"
    # Preferred: use this annotation instead of spec.loadBalancerIP (deprecated in K8s 1.24)
    service.beta.kubernetes.io/azure-load-balancer-ipv4: "<static-ip-address>"
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

## Ingress

### NGINX Ingress Controller (Helm)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2
```

Basic ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 80
```

### Application Gateway Ingress Controller (AGIC)

Enable via the AKS add-on:

```bash
az aks enable-addons \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --addons ingress-appgw \
  --appgw-name <app-gateway-name> \
  --appgw-subnet-cidr 10.225.0.0/16
```

## Network Policies

Network policies require a compatible CNI plugin (`--network-policy azure` or `--network-policy calico`). Clusters using **Azure CNI powered by Cilium** (`--network-dataplane cilium`) enforce both standard Kubernetes `NetworkPolicy` and Cilium-specific `CiliumNetworkPolicy` / `CiliumClusterwideNetworkPolicy` resources.

### Deny all ingress by default, then allow selectively

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

### Allow ingress from a specific namespace

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-monitoring
  namespace: <namespace>
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
```

### CiliumNetworkPolicy (Azure CNI powered by Cilium)

On AKS clusters with `--network-dataplane cilium`, you can use `CiliumNetworkPolicy` for L3-L7 policy enforcement with richer matching (DNS-based egress, HTTP-aware rules, etc.). These policies are additive — Cilium enforces both standard `NetworkPolicy` and `CiliumNetworkPolicy` simultaneously.

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-http-from-frontend
  namespace: <namespace>
spec:
  endpointSelector:
    matchLabels:
      app: my-api
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
          rules:
            http:
              - method: GET
                path: /api/.*
```

Cluster-wide policies use `CiliumClusterwideNetworkPolicy` (no namespace):

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: deny-external-egress
spec:
  endpointSelector: {}
  egressDeny:
    - toEntities:
        - world
```

DNS-based egress policy (allow traffic only to specific FQDNs):

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-egress-to-api
  namespace: <namespace>
spec:
  endpointSelector:
    matchLabels:
      app: my-app
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: ANY
          rules:
            dns:
              - matchPattern: "*.example.com"
    - toFQDNs:
        - matchPattern: "*.example.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

## DNS Configuration

AKS uses CoreDNS for cluster DNS. Check CoreDNS status:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### Custom CoreDNS configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  example.server: |
    example.com:53 {
        forward . 1.2.3.4
    }
```

```bash
kubectl apply -f coredns-custom.yaml
kubectl rollout restart deployment coredns -n kube-system
```

## Troubleshooting Connectivity

Always start troubleshooting from **inside the cluster** before escalating to Azure-level diagnostics. Most networking issues originate from misconfigurations in Kubernetes resources.

### Step 1: Check pod health and readiness

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

### Step 2: Verify services and endpoints

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

### Step 3: Test in-cluster connectivity

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
If neither works, investigate network policies or CNI issues.

### Step 4: Check network policies (including CiliumNetworkPolicy)

Network policies can silently block traffic. On AKS clusters with Cilium, **both** standard `NetworkPolicy` and `CiliumNetworkPolicy` / `CiliumClusterwideNetworkPolicy` are enforced simultaneously.

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

### Step 5: Diagnose DNS issues

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

### Step 6: Debug ingress issues

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

### Step 7: Check kube-proxy and CNI health

```bash
# Check kube-proxy pods (handles service-to-pod routing via iptables/IPVS)
kubectl get pods -n kube-system -l component=kube-proxy
kubectl logs -n kube-system -l component=kube-proxy --tail=30

# Check CNI plugin pods
kubectl get pods -n kube-system | grep -E 'azure-cni|cilium|calico'

# On a node, check iptables NAT rules for a service (via node debug)
kubectl debug node/<node-name> -it --image=nicolaka/netshoot -- chroot /host iptables -t nat -L KUBE-SERVICES | grep <service-name>
```

### Step 8: Escalate to Azure-level diagnostics

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

## References

- [AKS networking concepts](references/networking-concepts.md)
- [Azure CNI documentation](https://learn.microsoft.com/en-us/azure/aks/configure-azure-cni)
- [Azure network policies](https://learn.microsoft.com/en-us/azure/aks/use-network-policies)
- [AKS ingress documentation](https://learn.microsoft.com/en-us/azure/aks/ingress-basic)
