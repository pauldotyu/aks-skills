#!/bin/bash
set -euo pipefail
# Usage: ./create-nodepool.sh <RG> <CLUSTER> <WORKER_POOL> <VM_SIZE> <NODE_COUNT> [<MIN> <MAX>]
#
# Creates a User-mode worker node pool with --labels nodepool=worker.
# If MIN and MAX are provided, enables the cluster autoscaler.
# Omit MIN and MAX for a fixed-size pool.

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <RG> <CLUSTER> <WORKER_POOL> <VM_SIZE> <NODE_COUNT> [<MIN> <MAX>]"
  exit 1
fi

RG=$1; CLUSTER=$2; WORKER_POOL=$3; VM_SIZE=$4; NODE_COUNT=$5
MIN=${6:-}; MAX=${7:-}

AUTOSCALER_ARGS=""
if [[ -n "$MIN" && -n "$MAX" ]]; then
  AUTOSCALER_ARGS="--enable-cluster-autoscaler --min-count $MIN --max-count $MAX"
fi

echo "Preview:"
echo "az aks nodepool add --resource-group $RG --cluster-name $CLUSTER --name $WORKER_POOL --node-count $NODE_COUNT --mode User --node-vm-size $VM_SIZE --labels nodepool=worker $AUTOSCALER_ARGS"

read -p "Proceed to execute? (y/N) " confirm
if [[ "$confirm" == "y" ]]; then
  # shellcheck disable=SC2086
  az aks nodepool add \
    --resource-group "$RG" \
    --cluster-name "$CLUSTER" \
    --name "$WORKER_POOL" \
    --node-count "$NODE_COUNT" \
    --mode User \
    --node-vm-size "$VM_SIZE" \
    --labels nodepool=worker \
    $AUTOSCALER_ARGS

  echo ""
  echo "Waiting for nodes to become Ready..."
  echo "Run: kubectl get nodes -l agentpool=$WORKER_POOL -o wide"
else
  echo "Aborted."
  exit 0
fi