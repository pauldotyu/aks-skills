# Node Pool Best Practices

## System vs. User Node Pools

AKS clusters should separate system and user workloads into distinct node pools:

- **System pool (`--mode System`)** — Runs `kube-system` pods (CoreDNS, metrics-server, konnectivity-agent, etc.). Keep this pool small and dedicated.
- **User pool (`--mode User`)** — Runs application workloads. Scale independently based on app demand.

Azure Advisor flags clusters with only a System pool: **"Create a dedicated system node pool"**.

## Recommended Configuration

| Setting    | System pool                                     | User/Worker pool            |
| ---------- | ----------------------------------------------- | --------------------------- |
| Mode       | System                                          | User                        |
| VM size    | Standard_D2s_v3 or similar                      | Sized for your workload     |
| Node count | 1–3 (with autoscaler)                           | Based on workload demand    |
| Autoscaler | Optional (min 1)                                | Recommended                 |
| Labels     | Default                                         | `nodepool=worker`           |
| Taints     | `CriticalAddonsOnly=true:NoSchedule` (optional) | None (or workload-specific) |

## Scheduling Isolation

### Approach 1: nodeSelector (simple)

Add `nodeSelector` to Deployment specs to target the worker pool:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        agentpool: worker
```

### Approach 2: Taint the system pool (stronger)

Taint system nodes via the AKS API so only pods with matching tolerations can schedule there. Using `az aks nodepool update` ensures new nodes added during scale-out or upgrades inherit the taint automatically:

```bash
az aks nodepool update \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name <system-pool-name> \
  --node-taints CriticalAddonsOnly=true:NoSchedule
```

AKS system pods already tolerate `CriticalAddonsOnly`. Application pods without the toleration are excluded automatically.

### Approach 3: Node affinity (flexible)

Use `preferredDuringSchedulingIgnoredDuringExecution` for soft preference or `requiredDuringSchedulingIgnoredDuringExecution` for hard requirement:

```yaml
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: agentpool
                    operator: In
                    values:
                      - worker
```

## References

- [AKS system and user node pools](https://learn.microsoft.com/azure/aks/use-system-pools)
- [Taints and tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
- [Assigning pods to nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
