---
name: aks-nodepool-management
description: Ensure a dedicated User (worker) node pool exists and migrate application workloads off the System node pool. Use when Azure Advisor recommends "Create a dedicated system node pool", when adding User-mode node pools (az aks nodepool add --mode User), when tainting the system pool with CriticalAddonsOnly and restarting workloads to migrate them to a worker pool, or when scaling/updating existing node pools.
---

# AKS Node Pool Management

Create User-mode worker node pools, migrate application workloads off System node pools, and enforce workload isolation following AKS best practices.

> **Why?** Azure Advisor recommends "Create a dedicated system node pool" when a cluster has only a single System-mode pool. The fix is to add a User-mode worker pool and move application pods to it, keeping the system pool reserved for `kube-system` components.

> **Related skills:** For cluster provisioning, upgrades, and lifecycle, see [aks-cluster-management](../aks-cluster-management/SKILL.md). For networking (CNI, ingress, load balancers), see [aks-networking](../aks-networking/SKILL.md). For pod/node diagnostics, see [aks-troubleshooting](../aks-troubleshooting/SKILL.md). For monitoring, see [aks-monitoring](../aks-monitoring/SKILL.md).

## Prerequisites

- Azure CLI installed (`az --version`)
- Logged in to Azure (`az login` or a service principal / managed identity)
- `kubectl` configured for the target cluster (`az aks get-credentials`)
- Sufficient VM core quota in the target region for the new node pool

## Preconditions & Safety

- Perform in a **maintenance window** or **non-production cluster** first.
- Make **one change at a time** and verify before proceeding.
- Ensure at least one healthy worker pool exists **before** tainting the system pool or scaling it down.

## Step 1 — Discover Current Node Pools

Run read-only discovery and capture current state before any change:

```bash
# List node pools and check the "mode" column
az aks nodepool list \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  -o table

# If any pool already has Mode=User, you may not need to add one
# Capture state for rollback reference
az aks nodepool list \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  -o json > nodepools-backup.json

kubectl get nodes -o wide > nodes-backup.txt
kubectl get pods --all-namespaces -o wide > pods-backup.txt
```

## Step 2 — Create a Worker (User) Node Pool

### Without autoscaler

```bash
az aks nodepool add \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name worker \
  --node-count 3 \
  --node-vm-size Standard_D2s_v3 \
  --mode User \
  --labels nodepool=worker
```

### With autoscaler (recommended for production)

```bash
az aks nodepool add \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name worker \
  --node-count 3 \
  --node-vm-size Standard_D2s_v3 \
  --mode User \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 5 \
  --labels nodepool=worker
```

See [./scripts/create-nodepool.sh](./scripts/create-nodepool.sh) for an interactive wrapper script.

### Verify new nodes become Ready

```bash
kubectl get nodes -l agentpool=worker -o wide
# Wait until all worker nodes show STATUS=Ready
```

## Step 3 — Taint the System Pool

Taint the system pool so that user workloads **cannot** schedule there. AKS system pods already tolerate `CriticalAddonsOnly`, so they are unaffected.

```bash
az aks nodepool update \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name <system-pool-name> \
  --node-taints CriticalAddonsOnly=true:NoSchedule
```

> **Why `az aks nodepool update` instead of `kubectl taint`?** Setting taints via the AKS API ensures every node that joins the pool (e.g., during scale-out or upgrades) automatically receives the taint. `kubectl taint` only affects nodes that exist right now.

Once the taint is applied, existing pods on the system pool **continue running** — they are not evicted immediately. The next step triggers rescheduling.

## Step 4 — Migrate Workloads Off the System Pool

Restart application Deployments so their pods are rescheduled. Because the system pool now has a `NoSchedule` taint that application pods don't tolerate, the scheduler places them on the worker pool automatically:

```bash
# Restart a specific deployment
kubectl rollout restart deployment/<deployment-name> -n <namespace>

# Or restart all deployments in a namespace
kubectl rollout restart deployment -n <namespace>
```

```bash
# Verify pods moved to the worker pool
kubectl get pods -n <namespace> -o wide
```

No manifest changes required — the taint from Step 3 does the scheduling work.

## Step 5 — (Optional) Enable Autoscaling on the System Pool

```bash
az aks nodepool update \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name <system-pool-name> \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 3
```

## Step 6 — Post-Change Verification

```bash
# Application pods should appear on worker pool
kubectl get pods -A -o wide | grep worker

# System pool should have primarily kube-system pods
kubectl get pods -A -o wide | grep <system-pool-name>

# Check node health
kubectl get nodes -o wide
kubectl top nodes

# Check all pods are running
kubectl get pods -A --field-selector='status.phase!=Running,status.phase!=Succeeded'
```

## Rollback

If problems occur:

```bash
# 1. Remove the taint from the system pool to allow workloads back
az aks nodepool update \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name <system-pool-name> \
  --node-taints ""

# 2. Restart affected deployments to rebalance pods
kubectl rollout restart deployment/<deployment-name> -n <namespace>

# 3. Scale worker pool if more capacity is needed
az aks nodepool scale \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name worker \
  --node-count <desired-count>

# 4. Delete the worker pool entirely (only if empty of workloads)
az aks nodepool delete \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name worker
```

## Common Errors

| Error                             | Cause                                               | Fix                                                                   |
| --------------------------------- | --------------------------------------------------- | --------------------------------------------------------------------- |
| `QuotaExceeded`                   | VM core quota reached in the region                      | Request a quota increase under **Subscriptions > Usage + quotas**     |
| `SubnetIsFull`                    | No IPs available for new nodes (Azure CNI)               | Expand the subnet or switch to Azure CNI Overlay                      |
| Pods stuck in Pending after taint | No worker nodes available or matching tolerations missing | Verify worker pool is Ready (`kubectl get nodes`) and check pod events with `kubectl describe pod` |

## Scripts

- [./scripts/create-nodepool.sh](./scripts/create-nodepool.sh) — Interactive wrapper to create a User-mode node pool with autoscaler
