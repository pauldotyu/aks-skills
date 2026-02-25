# AKS Common Error Codes and Solutions

## Pod Exit Codes

| Exit Code | Meaning | Common Cause | Solution |
|-----------|---------|--------------|----------|
| 0 | Success | — | — |
| 1 | General error | Application crash | Check app logs |
| 2 | Misuse of shell built-in | Shell script error | Check entrypoint/command |
| 125 | Container failed to run | Docker daemon error | Check node logs |
| 126 | Command not executable | Permission issue | Check container entrypoint |
| 127 | Command not found | Missing binary | Verify container image |
| 128 | Invalid exit argument | — | Check app code |
| 130 | SIGINT (Ctrl+C) | Terminated manually | — |
| 137 | SIGKILL (OOMKilled) | Out of memory | Increase memory limits |
| 139 | SIGSEGV | Segmentation fault | App bug or incompatible deps |
| 143 | SIGTERM | Graceful shutdown | Normal; check if expected |

## Common Kubernetes Events

| Event Reason | Meaning | Solution |
|--------------|---------|----------|
| `FailedScheduling` | No node can fit the pod | Check resources, taints, affinity |
| `FailedMount` | Volume mount failed | Check PVC/PV status, storage class |
| `BackOff` | Container keeps crashing | Check logs with `--previous` |
| `Pulled` | Image pulled successfully | Normal |
| `Failed` | Image pull failed | Check image name, credentials |
| `Killing` | Container being killed | Normal on delete/update |
| `Unhealthy` | Liveness/readiness probe failed | Check probe configuration |
| `NodeNotReady` | Node is not ready | Check node conditions |
| `Evicted` | Pod evicted from node | Check resource pressure on node |

## AKS Provisioning Error Codes

| Error Code | Meaning | Solution |
|------------|---------|----------|
| `SubnetIsFull` | Subnet IP space exhausted | Use a larger subnet or overlay networking |
| `QuotaExceeded` | Azure quota limit hit | Request quota increase |
| `InvalidResourceReference` | Referenced resource doesn't exist | Check subnet, vnet, workspace IDs |
| `PodEvictionTimeout` | Pod could not be evicted during upgrade | Delete stuck pods manually |
| `UpgradeFailed` | Cluster upgrade failed | Check node pool status; retry |
| `NodePoolVersionMismatch` | Node pool version behind control plane | Upgrade node pools |

## HTTP Status Codes from the API Server

| Code | Meaning | Action |
|------|---------|--------|
| 401 | Unauthorized | Re-run `az aks get-credentials` |
| 403 | Forbidden | Check RBAC role bindings |
| 404 | Not found | Verify resource name and namespace |
| 429 | Rate limited | Reduce request frequency |
| 500 | Internal server error | Check control plane health |
| 503 | Service unavailable | API server may be restarting |
