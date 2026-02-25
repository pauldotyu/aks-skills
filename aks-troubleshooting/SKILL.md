---
name: aks-troubleshooting
description: Diagnose and resolve common Azure Kubernetes Service (AKS) issues. Use when pods are failing, nodes are not ready, the cluster API is unreachable, workloads are crashing or stuck in Pending/CrashLoopBackOff/OOMKilled states, or when investigating cluster-wide problems such as networking failures, resource exhaustion, or control plane errors.
license: MIT
metadata:
  author: pauldotyu
  version: "1.0"
compatibility: Requires kubectl connected to the target cluster and az CLI with an authenticated Azure session
---

# AKS Troubleshooting

This skill provides a systematic approach to diagnosing and resolving issues in Azure Kubernetes Service clusters.

## Quick Diagnostics

Always start with a cluster-level health check before diving deeper:

```bash
# Check node status
kubectl get nodes -o wide

# Check all pods across all namespaces
kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded'

# Check recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Check cluster component health (note: componentstatuses is deprecated since K8s 1.19)
kubectl get componentstatuses
# Preferred: check control plane pods directly
kubectl get pods -n kube-system
```

## Pod Troubleshooting

### Pod stuck in Pending

Possible causes: insufficient resources, node selector/affinity mismatch, PVC not bound, taint without toleration.

```bash
# Describe the pod for events
kubectl describe pod <pod-name> -n <namespace>

# Check if nodes have enough resources
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check PVCs if the pod uses persistent storage
kubectl get pvc -n <namespace>
```

### Pod in CrashLoopBackOff

```bash
# Get current logs
kubectl logs <pod-name> -n <namespace>

# Get logs from previous crashed container
kubectl logs <pod-name> -n <namespace> --previous

# Describe to see exit codes and events
kubectl describe pod <pod-name> -n <namespace>
```

Common causes and fixes:

- **Exit code 1**: Application error — check app logs for stack traces
- **Exit code 137 (OOMKilled)**: Increase memory limits or optimize the application
- **Exit code 139**: Segmentation fault — application bug or incompatible dependencies

### Pod in OOMKilled state

```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A 3 "OOMKilled"

# Check current resource requests/limits
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].resources}'
```

Increase memory limits:

```bash
kubectl set resources deployment/<deployment-name> \
  -n <namespace> \
  --limits=memory=512Mi \
  --requests=memory=256Mi
```

### Pod in ImagePullBackOff

```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Failed"
```

Common causes:

- Image name or tag is incorrect
- Private registry credentials missing — create or update the image pull secret
- Registry is unreachable from the node

```bash
# Create image pull secret for ACR
az acr credential show --name <acr-name>
kubectl create secret docker-registry acr-secret \
  --docker-server=<acr-name>.azurecr.io \
  --docker-username=<username> \
  --docker-password=<password> \
  -n <namespace>
```

## Node Troubleshooting

### Node in NotReady state

```bash
# Check node conditions
kubectl describe node <node-name> | grep -A 10 "Conditions:"

# SSH to the node (requires node access)
az aks nodepool show \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name <nodepool-name>

# Check kubelet logs on the node
journalctl -u kubelet -n 100
```

Common causes:

- Disk pressure: clean up unused images/volumes
- Memory pressure: reduce workload density
- Network issues: check CNI plugin status
- kubelet stopped: restart the VM or node pool

### Node disk pressure

```bash
# Identify nodes with disk pressure
kubectl get nodes -o custom-columns='NAME:.metadata.name,DISK:.status.conditions[?(@.type=="DiskPressure")].status'

# Clean up unused images on a node
kubectl debug node/<node-name> -it --image=ubuntu -- chroot /host crictl rmi --prune
```

## Service and Networking Troubleshooting

Always diagnose from **inside the cluster first** before checking Azure resources. Most connectivity issues are caused by Kubernetes resource misconfigurations, not Azure infrastructure.

### Service not reachable

Follow this order: pod health → service/endpoints → network policies → in-cluster connectivity → Azure resources.

```bash
# 1. Confirm target pods are Running and Ready
kubectl get pods -n <namespace> -o wide
kubectl describe pod <pod-name> -n <namespace>

# 2. Verify the application is listening on the expected port
kubectl exec <pod-name> -n <namespace> -- ss -tlnp

# 3. Check service configuration and endpoints
kubectl get service <service-name> -n <namespace> -o wide
kubectl get endpoints <service-name> -n <namespace>
kubectl get endpointslices -n <namespace> -l kubernetes.io/service-name=<service-name>

# 4. If endpoints are empty, compare service selector to pod labels
kubectl get service <service-name> -n <namespace> -o jsonpath='{.spec.selector}'
kubectl get pods -n <namespace> --show-labels

# 5. Check network policies BEFORE testing connectivity (silent drops waste time)
kubectl get networkpolicies -n <namespace>
kubectl describe networkpolicy <policy-name> -n <namespace>

# 5b. If using Cilium dataplane, also check CiliumNetworkPolicies
kubectl get ciliumnetworkpolicies -n <namespace>
kubectl get ciliumclusterwidenetworkpolicies
kubectl get ciliumendpoints -n <namespace>

# 6. Test connectivity from within the cluster
kubectl run debug --image=nicolaka/netshoot --rm -it -- bash
# Then inside the pod:
# curl -v http://<service-name>.<namespace>.svc.cluster.local
# nslookup <service-name>.<namespace>.svc.cluster.local
# curl -v http://<pod-ip>:<container-port>

# 7. Check kube-proxy is running (handles service routing)
# Note: clusters with Cilium in kube-proxy replacement mode won't have kube-proxy
kubectl get pods -n kube-system -l component=kube-proxy
kubectl logs -n kube-system -l component=kube-proxy --tail=30

# 7b. If using Cilium, check Cilium agent health instead
kubectl get pods -n kube-system -l k8s-app=cilium
kubectl exec -n kube-system <cilium-agent-pod> -- cilium status
```

### Network policy blocking traffic

Network policies silently drop packets with no error messages, making them hard to debug. On AKS clusters using Cilium (`--network-dataplane cilium`), **both** standard `NetworkPolicy` and `CiliumNetworkPolicy` / `CiliumClusterwideNetworkPolicy` are enforced together.

```bash
# List standard Kubernetes network policies
kubectl get networkpolicies -n <namespace>

# Check if a default-deny policy exists
kubectl get networkpolicies -n <namespace> -o jsonpath='{range .items[*]}{.metadata.name}: podSelector={.spec.podSelector}, policyTypes={.spec.policyTypes}{"\n"}{end}'

# Verify namespace labels match namespaceSelector rules
kubectl get namespace <source-namespace> --show-labels

# Describe the policy to inspect ingress/egress rules
kubectl describe networkpolicy <policy-name> -n <namespace>

# List CiliumNetworkPolicies in the namespace
kubectl get ciliumnetworkpolicies -n <namespace>
kubectl describe ciliumnetworkpolicy <policy-name> -n <namespace>

# List cluster-wide Cilium policies
kubectl get ciliumclusterwidenetworkpolicies
kubectl describe ciliumclusterwidenetworkpolicy <policy-name>

# Check which policies are applied to a specific pod via CiliumEndpoint
kubectl describe ciliumendpoint <pod-name> -n <namespace>

# Monitor real-time policy verdicts and drops on the Cilium agent
kubectl exec -n kube-system <cilium-agent-pod> -- cilium monitor --type drop
kubectl exec -n kube-system <cilium-agent-pod> -- cilium monitor --type policy-verdict

# Dump all active policies from the Cilium agent
kubectl exec -n kube-system <cilium-agent-pod> -- cilium policy get
```

Common network policy issues:

- Default-deny exists but no allow rule for the source pod/namespace
- Namespace label missing that the `namespaceSelector` expects
- Port in the policy doesn't match the actual container port
- Egress policy on the source side blocks outbound connections
- `CiliumNetworkPolicy` blocks traffic even when standard `NetworkPolicy` allows it (both are enforced independently)
- Cilium DNS-based egress policy blocks resolution because egress to CoreDNS on port 53 is not explicitly allowed
- `CiliumClusterwideNetworkPolicy` applies a blanket deny that overrides namespace-level allow rules

### Load balancer has no external IP

```bash
# Check service events first (most common diagnostic)
kubectl describe service <service-name> -n <namespace> | grep -A 10 "Events"

# Check if the service has endpoints (LB won't provision without endpoints)
kubectl get endpoints <service-name> -n <namespace>
```

Common causes:

- No ready endpoints — fix pod health or service selector first
- Quota limit on public IPs in the region
- AKS managed identity lacks network contributor role on the subnet

### DNS resolution failures

```bash
# Check CoreDNS pods are healthy
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Test DNS from a debug pod
kubectl run dnstest --image=busybox:1.28 --rm -it -- nslookup kubernetes.default

# Check resolv.conf in the affected pod
kubectl exec <pod-name> -n <namespace> -- cat /etc/resolv.conf

# Check for network policies blocking DNS (port 53 to kube-system)
kubectl get networkpolicies -n <namespace>
```

If internal DNS fails but external works, check CoreDNS configuration. If both fail, check CoreDNS pod health and network policies.

### Ingress not routing traffic

```bash
# Check ingress resource
kubectl get ingress -n <namespace>
kubectl describe ingress <ingress-name> -n <namespace>

# Check ingress controller pods are running
kubectl get pods -n ingress-nginx  # NGINX
kubectl get pods -n kube-system -l app=ingress-appgw  # AGIC

# Check ingress controller logs for errors
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50

# Verify the backend service has healthy endpoints
kubectl get endpoints <backend-service-name> -n <namespace>
```

## Resource and Quota Issues

```bash
# View resource quotas in a namespace
kubectl get resourcequota -n <namespace>
kubectl describe resourcequota -n <namespace>

# View LimitRange
kubectl get limitrange -n <namespace>

# View top nodes and pods
kubectl top nodes
kubectl top pods -A --sort-by=memory
```

## Control Plane and API Server Issues

```bash
# Check if API server is reachable
kubectl cluster-info

# View kube-system component pods
kubectl get pods -n kube-system

# Check recent warning events cluster-wide
kubectl get events -A --sort-by='.lastTimestamp' | grep -i warning | tail -30
```

## Azure-Level Diagnostics

Only escalate to Azure-level diagnostics after in-cluster checks have been exhausted:

```bash
# Collect AKS diagnostics logs
az aks kollect \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --storage-account <storage-account-name> \
  --sas-token <sas-token>

# Check Azure activity log for recent cluster operations
az monitor activity-log list \
  --resource-group <resource-group> \
  --offset 1h \
  --query "[?contains(resourceId, '<cluster-name>')].{time:eventTimestamp, op:operationName.localizedValue, status:status.localizedValue}" \
  -o table
```

Also use the built-in **AKS Diagnose and Solve Problems** blade in the Azure Portal for guided troubleshooting.

## Common Error Reference

See [references/error-codes.md](references/error-codes.md) for a list of common error codes and their solutions.

## References

- [AKS troubleshooting guide](https://learn.microsoft.com/en-us/azure/aks/troubleshooting)
- [Kubernetes pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [AKS diagnostics](https://learn.microsoft.com/en-us/azure/aks/aks-diagnostics)
