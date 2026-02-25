# aks-skills

A collection of [Agent Skills](https://agentskills.io) for Azure Kubernetes Service (AKS).

These skills give AI agents specialized knowledge and workflows for managing, troubleshooting, and operating AKS clusters.

## Skills

| Skill | Description |
|-------|-------------|
| [aks-cluster-management](./aks-cluster-management/) | Create, configure, scale, and upgrade AKS clusters using the Azure CLI and Bicep/ARM templates |
| [aks-troubleshooting](./aks-troubleshooting/) | Diagnose and resolve common AKS issues including pod failures, node problems, and cluster health |
| [aks-networking](./aks-networking/) | Configure and troubleshoot AKS networking including CNI plugins, ingress, load balancers, and DNS |
| [aks-monitoring](./aks-monitoring/) | Set up and query AKS monitoring with Azure Monitor, Container Insights, Prometheus, and Grafana |

## Usage

These skills follow the [Agent Skills open standard](https://agentskills.io/specification). To use them with a compatible agent, point the agent at this repository's root or individual skill directories.

## References

- [Agent Skills specification](https://agentskills.io/specification)
- [Azure Kubernetes Service documentation](https://learn.microsoft.com/en-us/azure/aks/)
- [Agent Skills Cookbook](https://github.com/anthropics/claude-cookbooks/tree/main/skills)