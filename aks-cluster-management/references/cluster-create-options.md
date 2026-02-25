# AKS Cluster Create Options Reference

Common options for `az aks create`.

## Identity

| Flag | Description |
|------|-------------|
| `--enable-managed-identity` | Use a system-assigned managed identity (recommended) |
| `--assign-identity <id>` | Use a user-assigned managed identity |
| `--enable-workload-identity` | Enable workload identity federation |
| `--enable-oidc-issuer` | Enable OIDC issuer URL (required for workload identity) |

## Networking

| Flag | Description |
|------|-------------|
| `--network-plugin azure` | Azure CNI (required for Windows nodes, advanced networking) |
| `--network-plugin kubenet` | Kubenet (default, simpler but limited) |
| `--network-plugin-mode overlay` | Azure CNI Overlay (recommended for large clusters) |
| `--network-policy azure` | Azure Network Policy Manager |
| `--network-policy calico` | Calico network policy |
| `--vnet-subnet-id <id>` | Existing subnet for nodes |
| `--service-cidr <cidr>` | IP range for Kubernetes services (default: 10.0.0.0/16) |
| `--dns-service-ip <ip>` | IP for the cluster DNS service |

## Node Pools

| Flag | Description |
|------|-------------|
| `--node-count <n>` | Initial node count (default: 3) |
| `--node-vm-size <size>` | VM size (default: Standard_DS2_v2) |
| `--os-disk-size-gb <n>` | OS disk size in GB |
| `--zones 1 2 3` | Availability zones for the node pool |
| `--enable-cluster-autoscaler` | Enable cluster autoscaler |
| `--min-count <n>` | Minimum nodes when autoscaler is enabled |
| `--max-count <n>` | Maximum nodes when autoscaler is enabled |

## Add-ons

| Flag | Description |
|------|-------------|
| `--enable-addons monitoring` | Enable Azure Monitor Container Insights |
| `--enable-addons azure-policy` | Enable Azure Policy for AKS |
| `--enable-addons virtual-node` | Enable virtual nodes (ACI) |
| `--enable-addons azure-keyvault-secrets-provider` | Enable Key Vault Secrets Provider |

## Security

| Flag | Description |
|------|-------------|
| `--enable-azure-rbac` | Enable Azure RBAC for Kubernetes authorization |
| `--enable-aad` | Enable AAD integration |
| `--aad-admin-group-object-ids <ids>` | AAD groups with cluster admin access |
| `--disable-local-accounts` | Disable local admin accounts (requires AAD) |
| `--private-cluster-enabled` | Create a private cluster (API server not public) |

## Recommended VM Sizes

| Workload | VM Size |
|----------|---------|
| Development | Standard_D2s_v3 (2 vCPU, 8 GB) |
| General production | Standard_D4s_v3 (4 vCPU, 16 GB) |
| Memory-intensive | Standard_E4s_v3 (4 vCPU, 32 GB) |
| Compute-intensive | Standard_F8s_v2 (8 vCPU, 16 GB) |
| GPU workloads | Standard_NC6s_v3 |
