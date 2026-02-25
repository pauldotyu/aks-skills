# aks-skills

A collection of [Agent Skills](https://agentskills.io) for Azure Kubernetes Service (AKS).

These skills give AI agents specialized knowledge and workflows for managing, troubleshooting, and operating AKS clusters.

## Skills

| Skill                                                                             | Description                                                                                                                                                                           |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [aks-cluster-management](./aks-cluster-management/)                               | Create, configure, scale, and upgrade AKS clusters using the Azure CLI                                                                                                                |
| [aks-monitoring](./aks-monitoring/)                                               | Set up and query AKS monitoring with Azure Monitor, Container Insights, Prometheus, and Grafana                                                                                       |
| [aks-networking](./aks-networking/)                                               | Configure and troubleshoot AKS networking including CNI plugins, ingress, load balancers, and DNS                                                                                     |
| [aks-troubleshooting](./aks-troubleshooting/)                                     | Diagnose and resolve common AKS issues including pod failures, node problems, and cluster health                                                                                      |
| [aks-workload-identity-troubleshooting](./aks-workload-identity-troubleshooting/) | Troubleshoot workload identity configuration in AKS clusters, covering Azure User-Assigned Managed Identity, Microsoft Entra ID App Registration, and federated identity credentials. |

## Usage

These skills follow the [Agent Skills open standard](https://agentskills.io/specification). To use them with a compatible agent, point the agent at this repository's root or individual skill directories.

These skills are automatically discovered by compatible agents (e.g., GitHub Copilot coding agent) when working in this repository. When you ask an agent to help with an AKS task, it will load the relevant skill and follow its instructions.

## References

- [Azure Kubernetes Service Troubleshooting Documentation](https://learn.microsoft.com/troubleshoot/azure/azure-kubernetes/welcome-azure-kubernetes)
- [Agent Skills specification](https://agentskills.io/specification)
- [Agent Skills Cookbook](https://github.com/anthropics/claude-cookbooks/tree/main/skills)
