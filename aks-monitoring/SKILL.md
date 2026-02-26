---
name: aks-monitoring
description: Set up and query monitoring for Azure Kubernetes Service (AKS) clusters. Use when enabling Azure Monitor Container Insights, configuring Prometheus and Grafana, querying cluster metrics and logs, setting up alerts for resource usage or pod failures, or investigating performance issues using monitoring data.
---

# AKS Monitoring

This skill covers setting up and using monitoring for AKS clusters using Azure Monitor Container Insights, Prometheus, and Grafana.

## Azure Monitor Container Insights

### Enable on an existing cluster

```bash
# Create a Log Analytics workspace
az monitor log-analytics workspace create \
  --resource-group <resource-group> \
  --workspace-name <workspace-name> \
  --location <location>

WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group <resource-group> \
  --workspace-name <workspace-name> \
  --query "id" -o tsv)

# Enable the monitoring add-on
az aks enable-addons \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --addons monitoring \
  --workspace-resource-id "$WORKSPACE_ID"
```

### Query Container Insights logs

In the Azure Portal Log Analytics workspace, use these KQL queries:

```kql
// CPU usage by pod (last 1 hour)
KubePodInventory
| where TimeGenerated > ago(1h)
| where ClusterName == "<cluster-name>"
| extend ContainerName = tostring(split(ContainerName, "/")[1])
| join (
    Perf
    | where ObjectName == "K8SContainer"
    | where CounterName == "cpuUsageNanoCores"
    | summarize AvgCPU = avg(CounterValue) by Computer, InstanceName
) on $left.ContainerID == $right.InstanceName
| project PodName, Namespace, ContainerName, AvgCPU
| order by AvgCPU desc
```

```kql
// Memory usage by pod (last 1 hour)
KubePodInventory
| where TimeGenerated > ago(1h)
| where ClusterName == "<cluster-name>"
| join (
    Perf
    | where ObjectName == "K8SContainer"
    | where CounterName == "memoryRssBytes"
    | summarize AvgMemory = avg(CounterValue) by InstanceName
) on $left.ContainerID == $right.InstanceName
| project PodName, Namespace, AvgMemoryMB = AvgMemory / 1048576
| order by AvgMemoryMB desc
```

```kql
// Pod restarts in last 24 hours
KubePodInventory
| where TimeGenerated > ago(24h)
| where ClusterName == "<cluster-name>"
| where PodRestartCount > 0
| summarize MaxRestarts = max(PodRestartCount) by PodName, Namespace
| order by MaxRestarts desc
```

```kql
// Node resource utilization
KubeNodeInventory
| where TimeGenerated > ago(1h)
| where ClusterName == "<cluster-name>"
| join (
    Perf
    | where ObjectName == "K8SNode"
    | where CounterName in ("cpuUsagePercentage", "memoryWorkingSetPercentage")
    | summarize AvgUsage = avg(CounterValue) by Computer, CounterName
) on Computer
| project Node = Computer, CounterName, AvgUsage
```

## Prometheus and Grafana

### Deploy kube-prometheus-stack (recommended)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=<secure-password>
```

### Access Grafana

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# Open http://localhost:3000 in your browser
# Default credentials: admin / <password set above>
```

### Common Prometheus queries (PromQL)

```promql
# CPU usage by pod
sum(rate(container_cpu_usage_seconds_total{namespace="<namespace>"}[5m])) by (pod)

# Memory usage by pod (MB)
sum(container_memory_working_set_bytes{namespace="<namespace>"}) by (pod) / 1048576

# Pod restart count
sum(kube_pod_container_status_restarts_total{namespace="<namespace>"}) by (pod)

# Node CPU usage percentage
(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)) * 100

# Pod not ready
kube_pod_status_ready{condition="false"} == 1

# Pending pods
kube_pod_status_phase{phase="Pending"} == 1
```

### Scrape AKS managed Prometheus

AKS supports a managed Prometheus experience integrated with Azure Monitor:

```bash
az aks update \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id <azure-monitor-workspace-id>
```

## Alerting

### Alert when pods are in CrashLoopBackOff

Using a Prometheus alert rule (requires managed Prometheus):

```yaml
apiVersion: alerts.monitor.azure.com/v1
kind: PrometheusRuleGroup
metadata:
  name: crashloopbackoff-alert
spec:
  scopes:
    - /subscriptions/<sub-id>/resourceGroups/<rg>/providers/microsoft.monitor/accounts/<azure-monitor-workspace>
  clusterName: <cluster-name>
  rules:
    - alert: PodCrashLoopBackOff
      expression: kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} > 0
      for: 5m
      severity: 3
      annotations:
        description: "Pod {{ $labels.namespace }}/{{ $labels.pod }} is in CrashLoopBackOff"
```

Alternatively, use a Container Insights log-based alert via scheduled query:

```bash
az monitor scheduled-query create \
  --resource-group <resource-group> \
  --name "CrashLoopBackOff Alert" \
  --scopes "/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace-name>" \
  --condition "count 'KubePodInventory | where ContainerStatusReason == \"CrashLoopBackOff\"' > 0" \
  --evaluation-frequency 5m \
  --window-size 10m \
  --severity 2
```

### Alert on node CPU > 80%

Using a Prometheus alert rule (requires managed Prometheus):

```yaml
apiVersion: alerts.monitor.azure.com/v1
kind: PrometheusRuleGroup
metadata:
  name: node-cpu-alert
spec:
  scopes:
    - /subscriptions/<sub-id>/resourceGroups/<rg>/providers/microsoft.monitor/accounts/<azure-monitor-workspace>
  clusterName: <cluster-name>
  rules:
    - alert: HighNodeCPU
      expression: (1 - avg by (instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 80
      for: 5m
      severity: 2
      annotations:
        description: "Node {{ $labels.instance }} CPU usage is above 80%"
```

## kubectl-Based Monitoring

### View resource usage

```bash
# Node resource usage
kubectl top nodes

# Pod resource usage (all namespaces, sorted by memory)
kubectl top pods -A --sort-by=memory

# Pod resource usage in a namespace
kubectl top pods -n <namespace>
```

### Watch pod status

```bash
# Live-update pod status
kubectl get pods -n <namespace> -w

# Watch events
kubectl get events -n <namespace> --sort-by='.lastTimestamp' -w
```

## References

- [Monitoring options](./references/monitoring-options.md)
- [Azure Monitor Container Insights](https://learn.microsoft.com/en-us/azure/aks/monitor-aks)
- [AKS managed Prometheus](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/prometheus-metrics-enable)
- [Grafana integration with AKS](https://learn.microsoft.com/en-us/azure/managed-grafana/quickstart-managed-grafana-portal)
