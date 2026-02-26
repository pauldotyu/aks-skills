---
name: aks-skills
description: Azure Kubernetes Service (AKS) skill collection. Use when working with AKS clusters, including provisioning, networking, monitoring, troubleshooting, and workload identity. Routes to specialized sub-skills for each domain.
---

# AKS Skills

A collection of specialized skills for Azure Kubernetes Service (AKS) operations. Each skill below covers a specific domain — activate the one that matches the task.

## Available Skills

| Task              | Skill                                                       | When to use                                                               |
| ----------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------- |
| Cluster lifecycle | [aks-cluster-management](./aks-cluster-management/SKILL.md) | Creating, scaling, upgrading, stopping, or deleting AKS clusters          |
| Monitoring        | [aks-monitoring](./aks-monitoring/SKILL.md)                 | Container Insights, Prometheus, Grafana, KQL/PromQL queries, alerts       |
| Networking        | [aks-networking](./aks-networking/SKILL.md)                 | CNI plugins, ingress, load balancers, network policies, DNS, connectivity |
| Troubleshooting   | [aks-troubleshooting](./aks-troubleshooting/SKILL.md)       | Pod failures, node issues, control plane problems, resource quotas        |
| Workload identity | [aks-workload-identity](./aks-workload-identity/SKILL.md)   | OIDC federation, managed identities, federated credentials, AADSTS errors |

## Skill Selection Guide

- **"Create a cluster" / "add a node pool" / "upgrade Kubernetes"** → aks-cluster-management
- **"Enable monitoring" / "write a KQL query" / "set up alerts"** → aks-monitoring
- **"Configure ingress" / "pod can't connect" / "network policy"** → aks-networking
- **"Pod is crashing" / "node NotReady" / "OOMKilled"** → aks-troubleshooting
- **"Set up workload identity" / "AADSTS70021" / "federated credential"** → aks-workload-identity
