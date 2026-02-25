# aks-skills

A collection of [Agent Skills](https://agentskills.io) for Azure Kubernetes Service (AKS).

These skills give AI agents specialized knowledge and workflows for managing, troubleshooting, and operating AKS clusters.

## Skills

| Skill                                               | Description                                                                                                                                                                                |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [aks-cluster-management](./aks-cluster-management/) | Create, configure, scale, and upgrade AKS clusters using the Azure CLI                                                                                                                     |
| [aks-monitoring](./aks-monitoring/)                 | Set up and query AKS monitoring with Azure Monitor, Container Insights, Prometheus, and Grafana                                                                                            |
| [aks-networking](./aks-networking/)                 | Configure and troubleshoot AKS networking including CNI plugins, ingress, load balancers, and DNS                                                                                          |
| [aks-troubleshooting](./aks-troubleshooting/)       | Diagnose and resolve common AKS issues including pod failures, node problems, and cluster health                                                                                           |
| [aks-workload-identity](./aks-workload-identity/)   | Configure and troubleshoot Microsoft Entra Workload ID on AKS clusters, covering OIDC federation, managed identities, app registrations, federated credentials, and service account setup. |

## References

- [Azure Kubernetes Service Documentation](https://learn.microsoft.com/azure/aks/)
- [Azure Kubernetes Service Troubleshooting Documentation](https://learn.microsoft.com/troubleshoot/azure/azure-kubernetes/welcome-azure-kubernetes)
- [Agent Skills specification](https://agentskills.io/specification)
