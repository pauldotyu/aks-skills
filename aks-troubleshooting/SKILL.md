---
name: aks-troubleshooting
description: Diagnose and resolve Azure Kubernetes Service (AKS) pod, node, and control plane issues. Use when pods are stuck in Pending, CrashLoopBackOff, OOMKilled, ImagePullBackOff, or Error states, nodes show NotReady or SchedulingDisabled, the API server is unreachable, containers crash with non-zero exit codes, resource quotas are exceeded, or persistent volume claims fail to bind.
---

# AKS Troubleshooting

This skill covers pod, node, resource, and control plane troubleshooting for Azure Kubernetes Service clusters.

> **Related skills:** For networking and connectivity issues, see [aks-networking](../aks-networking/SKILL.md). For cluster provisioning or upgrade failures, see [aks-cluster-management](../aks-cluster-management/SKILL.md). For workload identity token errors, see [aks-workload-identity](../aks-workload-identity/SKILL.md). For monitoring and alerting, see [aks-monitoring](../aks-monitoring/SKILL.md).

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

See [./references/error-codes.md](./references/error-codes.md) for a list of common error codes and their solutions.

## References

- [AKS troubleshooting guide](https://learn.microsoft.com/en-us/azure/aks/troubleshooting)
- [Kubernetes pod lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [AKS diagnostics](https://learn.microsoft.com/en-us/azure/aks/aks-diagnostics)
