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

## Installation

### With kagent

Add the skill container image when creating an agent in the kagent dashboard:

```
ghcr.io/pauldotyu/aks-skills:latest
```

Or reference it in your Agent CR:

```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: aks-agent
spec:
  skills:
    refs:
      - ghcr.io/pauldotyu/aks-skills:latest
  # ...
```

### From container image

Pull the image and extract skill files using Docker:

```bash
docker create --name aks-skills ghcr.io/pauldotyu/aks-skills:v0.1.0
docker cp aks-skills:/ ./aks-skills
docker rm aks-skills
```

### From source

Clone the repository directly:

```bash
git clone https://github.com/pauldotyu/aks-skills.git
```

## Usage

These skills follow the [Agent Skills open standard](https://agentskills.io/specification). To use them with a compatible agent, point the agent at this repository's root or individual skill directories.

These skills are automatically discovered by compatible agents (e.g., GitHub Copilot coding agent) when working in this repository. When you ask an agent to help with an AKS task, it will load the relevant skill and follow its instructions.

## Publishing

This repository uses a GitHub Actions workflow to build and push a skill container image to GitHub Container Registry. To publish a new version:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow builds a `FROM scratch` container image containing all skill directories and pushes it to `ghcr.io/pauldotyu/aks-skills:<tag>`. This image is compatible with [kagent](https://kagent.dev)'s "Skill Container Images" feature.

## References

- [Azure Kubernetes Service Troubleshooting Documentation](https://learn.microsoft.com/troubleshoot/azure/azure-kubernetes/welcome-azure-kubernetes)
- [Agent Skills specification](https://agentskills.io/specification)
- [Agent Skills Cookbook](https://github.com/anthropics/claude-cookbooks/tree/main/skills)
