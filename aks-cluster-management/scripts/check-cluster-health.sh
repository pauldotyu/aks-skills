#!/usr/bin/env bash
# check-cluster-health.sh
# Usage: ./check-cluster-health.sh <resource-group> <cluster-name>
# Reports the overall health status of an AKS cluster and its node pools.

set -euo pipefail

RESOURCE_GROUP="${1:?Usage: $0 <resource-group> <cluster-name>}"
CLUSTER_NAME="${2:?Usage: $0 <resource-group> <cluster-name>}"

echo "=== AKS Cluster Health: $CLUSTER_NAME ==="
echo ""

# Cluster provisioning state
PROVISIONING_STATE=$(az aks show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --query "provisioningState" \
  --output tsv)

echo "Provisioning state: $PROVISIONING_STATE"

# Kubernetes version
K8S_VERSION=$(az aks show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --query "kubernetesVersion" \
  --output tsv)

echo "Kubernetes version: $K8S_VERSION"
echo ""

# Node pools
echo "=== Node Pools ==="
az aks nodepool list \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$CLUSTER_NAME" \
  --query "[].{Name:name,Count:count,VMSize:vmSize,State:provisioningState,Version:orchestratorVersion}" \
  --output table

echo ""

# Available upgrades
echo "=== Available Upgrades ==="
az aks get-upgrades \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CLUSTER_NAME" \
  --query "agentPoolProfiles[0].upgrades[].kubernetesVersion" \
  --output tsv 2>/dev/null || echo "No upgrades available"
