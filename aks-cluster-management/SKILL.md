---
name: aks-cluster-management
description: Create, configure, scale, and upgrade Azure Kubernetes Service (AKS) clusters. Use when the user needs to provision a new AKS cluster, change cluster configuration, scale node pools, upgrade Kubernetes versions, manage cluster credentials, or perform lifecycle operations on AKS clusters.
license: MIT
metadata:
  author: pauldotyu
  version: "1.0"
compatibility: Requires Azure CLI (az) with the aks extension installed and an authenticated Azure session
---

# AKS Cluster Management

This skill covers the full lifecycle of Azure Kubernetes Service clusters: provisioning, configuration, scaling, upgrading, and deletion.

## Prerequisites

- Azure CLI installed (`az --version`)
- Logged in to Azure (`az login` or a service principal / managed identity)
- The `aks-preview` extension if preview features are needed (`az extension add --name aks-preview`)

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

See [references/cluster-create-options.md](references/cluster-create-options.md) for all available options.

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

## References

- [Cluster create options](references/cluster-create-options.md)
- [Azure AKS documentation](https://learn.microsoft.com/en-us/azure/aks/)
- [AKS best practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
