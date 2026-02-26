---
name: aks-cluster-management
description: Create, configure, scale, upgrade, stop, start, and delete Azure Kubernetes Service (AKS) clusters using Azure CLI. Use when provisioning new AKS clusters (az aks create), scaling or adding node pools, enabling cluster autoscaler, upgrading Kubernetes versions, rotating credentials or certificates, creating private clusters, managing spot node pools, or performing any cluster lifecycle operation.
---

# AKS Cluster Management

This skill covers the full lifecycle of Azure Kubernetes Service clusters: provisioning, configuration, scaling, upgrading, and deletion.

> **Related skills:** For network configuration (CNI, ingress, load balancers), see [aks-networking](../aks-networking/SKILL.md). For monitoring setup, see [aks-monitoring](../aks-monitoring/SKILL.md). For pod/node diagnostics, see [aks-troubleshooting](../aks-troubleshooting/SKILL.md). For workload identity, see [aks-workload-identity](../aks-workload-identity/SKILL.md).

## Prerequisites

- Azure CLI installed (`az --version`)
- Logged in to Azure (`az login` or a service principal / managed identity)
- The `aks-preview` extension if preview features are needed (`az extension add --name aks-preview`)

## Pre-flight Checklist

Before creating a cluster, verify these requirements to avoid common provisioning failures:

```bash
# 1. Verify the Microsoft.ContainerService provider is registered
az provider show --namespace Microsoft.ContainerService --query "registrationState" --output tsv
# If not registered:
az provider register --namespace Microsoft.ContainerService

# 2. Check VM quota in the target region
az vm list-usage --location <location> --output table | grep -i "Standard D"

# 3. If using an existing subnet, verify available IP addresses
az network vnet subnet show \
  --resource-group <vnet-resource-group> \
  --vnet-name <vnet-name> \
  --name <subnet-name> \
  --query "{addressPrefix:addressPrefix, availableIPs:ipConfigurations | length(@)}" \
  --output table

# 4. Check for Azure Policy assignments that may block creation
az policy assignment list --query "[?enforcementMode=='Default'].{Name:displayName, Policy:policyDefinitionId}" --output table

# 5. Verify you have sufficient permissions (Contributor + RBAC Admin on the resource group)
az role assignment list --assignee $(az ad signed-in-user show --query id -o tsv) --scope /subscriptions/$(az account show --query id -o tsv)/resourceGroups/<resource-group> --output table
```

> **Tip:** For Azure CNI (non-overlay), plan for at least (node count × max pods per node) + nodes IP addresses in your subnet. The default max pods is 30, so a 3-node cluster needs ~93 IPs minimum. Azure CNI Overlay avoids this requirement.

## Creating a Cluster

### Basic cluster

```bash
az group create --name <resource-group> --location <location>

az aks create \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --node-count 3 \
  --node-vm-size Standard_D2s_v3 \
  --generate-ssh-keys
```

### Production-ready cluster (recommended settings)

```bash
az aks create \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --node-count 3 \
  --node-vm-size Standard_D4s_v3 \
  --enable-managed-identity \
  --network-plugin azure \
  --network-policy azure \
  --enable-addons monitoring \
  --workspace-resource-id <log-analytics-workspace-id> \
  --zones 1 2 3 \
  --generate-ssh-keys
```

See [./references/cluster-create-options.md](./references/cluster-create-options.md) for all available options.

### Common creation errors

| Error                                            | Cause                                                              | Fix                                                                                                                                                                          |
| ------------------------------------------------ | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `MissingSubscriptionRegistration`                | `Microsoft.ContainerService` not registered                        | `az provider register --namespace Microsoft.ContainerService`                                                                                                                |
| `SubnetIsFull`                                   | Subnet has no available IP addresses                               | Use a larger subnet (`/16` or `/20`) or switch to Azure CNI Overlay (`--network-plugin-mode overlay`)                                                                        |
| `QuotaExceeded`                                  | VM core quota limit reached in the region                          | Request a quota increase in the Azure portal under **Subscriptions > Usage + quotas**                                                                                        |
| `RequestDisallowedByPolicy`                      | Azure Policy is blocking the operation                             | Check policy assignments with `az policy assignment list`; request an exemption or adjust parameters                                                                         |
| `OutboundConnFailVMExtensionError` (50)          | Nodes cannot reach required outbound endpoints during provisioning | Verify NSG/firewall rules allow outbound to AKS required endpoints; see [AKS egress traffic docs](https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress) |
| `K8SAPIServerConnFailVMExtensionError` (51)      | Nodes cannot connect to the API server                             | Check NSG rules, private DNS zones (for private clusters), and UDR configuration                                                                                             |
| `K8SAPIServerDNSLookupFailVMExtensionError` (52) | DNS resolution for API server failed                               | Verify DNS settings and that the VNet can resolve Azure public/private DNS                                                                                                   |
| `SubscriptionRequestsThrottled` (429)            | Too many Azure API requests                                        | Wait and retry; reduce parallel deployments against the same subscription                                                                                                    |

For a complete error code reference, see the [AKS troubleshooting skill](../aks-troubleshooting/SKILL.md) and [AKS error codes](../aks-troubleshooting/references/error-codes.md).

## Getting Cluster Credentials

```bash
az aks get-credentials \
  --resource-group <resource-group> \
  --name <cluster-name>
```

Add `--overwrite-existing` to replace existing kubeconfig entries.

## Scaling Node Pools

### Scale a node pool

```bash
az aks scale \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --node-count <count> \
  --nodepool-name <nodepool-name>
```

### Enable cluster autoscaler

```bash
az aks update \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 10 \
  --nodepool-name <nodepool-name>
```

### Common scaling errors

| Error                          | Cause                                                                 | Fix                                                                              |
| ------------------------------ | --------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| `QuotaExceeded`                | VM core quota reached when scaling out                                | Request quota increase; check with `az vm list-usage --location <location>`      |
| `SubnetIsFull`                 | No IPs available for new nodes (Azure CNI)                            | Expand the subnet or switch to Azure CNI Overlay                                 |
| Autoscaler fails to scale up   | Insufficient quota, pod anti-affinity, or taint/toleration mismatches | Check autoscaler status: `kubectl -n kube-system logs -l app=cluster-autoscaler` |
| Autoscaler fails to scale down | PDB blocks eviction or pods without controller                        | Review `kubectl get pdb -A` and ensure pods are managed by a controller          |

For large-scale clusters (>1000 nodes), see [Troubleshoot large AKS clusters](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/aks-at-scale-troubleshoot-guide).

## Adding Node Pools

```bash
az aks nodepool add \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name <nodepool-name> \
  --node-count 3 \
  --node-vm-size Standard_D4s_v3 \
  --zones 1 2 3
```

For spot node pools (cost optimization):

```bash
az aks nodepool add \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name spotnp \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --node-count 3
```

## Upgrading a Cluster

### Check available upgrades

```bash
az aks get-upgrades \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --output table
```

### Upgrade the control plane

```bash
az aks upgrade \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --kubernetes-version <version>
```

### Upgrade a specific node pool

```bash
az aks nodepool upgrade \
  --resource-group <resource-group> \
  --cluster-name <cluster-name> \
  --name <nodepool-name> \
  --kubernetes-version <version>
```

### Common upgrade errors

| Error                       | Cause                                           | Fix                                                                                                                                   |
| --------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `PodDrainFailure`           | Pods cannot be evicted (PDB or stuck finalizer) | Delete stuck pods manually: `kubectl delete pod <pod> --grace-period=0 --force`                                                       |
| `SubnetIsFull`              | Surge upgrade needs extra IPs for new nodes     | Free IPs or use `--max-surge 1` to reduce IP demand                                                                                   |
| `PublicIPCountLimitReached` | Azure public IP quota exhausted                 | Request quota increase for public IPs in the region                                                                                   |
| NSG rules block upgrade     | NSG on subnet blocks required AKS traffic       | Ensure NSG allows traffic per [AKS required network rules](https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress) |
| `UpgradeFailed`             | Generic upgrade failure                         | Check node pool status with `az aks nodepool show`; cordon/drain problematic nodes and retry                                          |

> **Tip:** Always upgrade the control plane first, then upgrade node pools one at a time. Use `--max-surge` to control how many extra nodes are created during the rolling upgrade.

## Stopping and Starting a Cluster

Stop a cluster to save costs when not in use:

```bash
az aks stop \
  --resource-group <resource-group> \
  --name <cluster-name>

az aks start \
  --resource-group <resource-group> \
  --name <cluster-name>
```

## Deleting a Cluster

```bash
az aks delete \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --yes
```

### Common deletion errors

| Error                                            | Cause                                             | Fix                                                                 |
| ------------------------------------------------ | ------------------------------------------------- | ------------------------------------------------------------------- |
| `CannotDeleteLoadBalancerWithPrivateLinkService` | Load balancer has a Private Link Service attached | Delete the Private Link Service first, then delete the cluster      |
| `LoadBalancerInUseByVirtualMachineScaleSet`      | VMSS still references the LB                      | Wait for node pool deletion to complete or manually detach the VMSS |
| `PublicIPAddressCannotBeDeleted`                 | Public IP is still associated with a resource     | Disassociate the IP from the load balancer or NIC before deleting   |
| `InUseRouteTableCannotBeDeleted`                 | Route table still attached to a subnet            | Remove the subnet association before deletion                       |

## Listing Clusters

```bash
# All clusters in a subscription
az aks list --output table

# Clusters in a resource group
az aks list \
  --resource-group <resource-group> \
  --output table
```

## Checking Cluster Status

```bash
az aks show \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --query "provisioningState" \
  --output tsv
```

For a comprehensive health check (provisioning state, Kubernetes version, node pools, and available upgrades), run the bundled executable script:

```bash
./scripts/check-cluster-health.sh <resource-group> <cluster-name>
```

See [./scripts/check-cluster-health.sh](./scripts/check-cluster-health.sh) for the full script.

## Common Patterns

### Enable workload identity

```bash
az aks update \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --enable-oidc-issuer \
  --enable-workload-identity
```

### Enable Azure Key Vault secrets provider

```bash
az aks enable-addons \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --addons azure-keyvault-secrets-provider
```

### Rotate cluster certificates

```bash
az aks rotate-certs \
  --resource-group <resource-group> \
  --name <cluster-name>
```

### Create a private cluster

```bash
az aks create \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --enable-managed-identity \
  --network-plugin azure \
  --private-cluster-enabled \
  --generate-ssh-keys
```

> **Important — Private cluster connectivity:** When `--private-cluster-enabled` is set, the API server gets a private IP address only. You **cannot** run `kubectl` commands from outside the cluster's VNet. Access options:
>
> - **Azure VM in the same VNet** — deploy a jumpbox or dev VM in the cluster VNet or a peered VNet.
> - **VPN / ExpressRoute** — connect your on-premises or local machine to the VNet via VPN gateway or ExpressRoute.
> - **`az aks command invoke`** — run commands remotely without direct network access:
>   ```bash
>   az aks command invoke \
>     --resource-group <resource-group> \
>     --name <cluster-name> \
>     --command "kubectl get nodes"
>   ```
> - **Private endpoint from another VNet** — create a private endpoint in a different VNet with VNet peering.
>
> Also verify that the private DNS zone (`privatelink.<region>.azmk8s.io`) is linked to any VNet that needs to resolve the API server hostname.

## Troubleshooting

For detailed troubleshooting guidance beyond the error tables above, see these related skills:

- **[AKS Troubleshooting](../aks-troubleshooting/SKILL.md)** — systematic diagnostics for pods, nodes, services, networking, and control plane issues
- **[AKS Troubleshooting Error Codes](../aks-troubleshooting/references/error-codes.md)** — comprehensive error code reference (pod exit codes, Kubernetes events, AKS provisioning errors, API server HTTP codes)
- **[AKS Networking](../aks-networking/SKILL.md)** — network plugin configuration, load balancers, ingress, network policies, and DNS troubleshooting
- **[AKS Workload Identity](../aks-workload-identity/SKILL.md)** — OIDC federation issues, AADSTS errors, and service account misconfigurations
- **[Microsoft AKS Troubleshooting Docs](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/welcome-azure-kubernetes)** — official troubleshooting documentation covering create, upgrade, delete, scale, and connectivity issues

## References

- [Cluster create options](./references/cluster-create-options.md)
- [Cluster health check script](./scripts/check-cluster-health.sh) — executable script that reports provisioning state, Kubernetes version, node pool status, and available upgrades
- [Azure AKS documentation](https://learn.microsoft.com/en-us/azure/aks/)
- [AKS best practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
- [AKS troubleshooting documentation](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/welcome-azure-kubernetes)
- [AKS required outbound network rules](https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress)
- [AKS private cluster overview](https://learn.microsoft.com/en-us/azure/aks/private-clusters)
