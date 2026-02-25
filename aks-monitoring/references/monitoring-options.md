# AKS Monitoring Options

## Monitoring Solutions Comparison

| Solution | Type | Best For |
|----------|------|----------|
| Azure Monitor Container Insights | Managed Azure service | Production clusters, Azure-native environments |
| Managed Prometheus + Grafana | Managed Azure service | Teams familiar with Prometheus/Grafana |
| Self-hosted kube-prometheus-stack | Open source (Helm) | Full control, custom dashboards |
| Datadog / Dynatrace / New Relic | Third-party | Enterprises with existing APM investments |

## Azure Monitor Container Insights

- **Logs**: Stored in a Log Analytics workspace, queried with KQL
- **Metrics**: CPU, memory, disk, network per node and container
- **Dashboards**: Pre-built dashboards in the Azure Portal
- **Alerting**: Integrated with Azure Monitor Alerts
- **Cost**: Based on data ingestion volume into Log Analytics

### Key tables in Log Analytics

| Table | Contents |
|-------|----------|
| `KubePodInventory` | Pod status, restarts, namespace, labels |
| `KubeNodeInventory` | Node status, conditions, capacity |
| `KubeEvents` | Kubernetes events (warnings, errors) |
| `KubeServices` | Service details |
| `ContainerLog` | Container stdout/stderr logs |
| `InsightsMetrics` | Performance metrics (CPU, memory) |
| `Perf` | Performance counters from nodes and containers |

## Managed Prometheus with Azure Monitor Workspace

- No infrastructure to manage
- Metrics stored in Azure Monitor workspace
- Queried with PromQL via Grafana or Azure Workbooks
- Integrates with Azure Managed Grafana
- Supports custom scrape configurations via `PodMonitor` and `ServiceMonitor` CRDs

### Enabling managed Prometheus

Requirements:
- Azure Monitor workspace (different from Log Analytics workspace)
- AKS cluster with managed identity
- Optional: Azure Managed Grafana for visualization

## Key Metrics to Monitor

### Cluster health

| Metric | Alert Threshold |
|--------|----------------|
| Node CPU usage | > 80% sustained |
| Node memory usage | > 85% sustained |
| Node disk usage | > 80% |
| Pod restart count | > 5 in 1 hour |
| Pending pods | > 0 for > 5 minutes |
| NotReady nodes | > 0 |

### Application performance

| Metric | Alert Threshold |
|--------|----------------|
| HTTP error rate | > 1% |
| P99 request latency | > 2 seconds (application-specific) |
| Request queue depth | > 100 (application-specific) |

## Log Retention

Default Log Analytics retention is 30 days. For compliance:

```bash
az monitor log-analytics workspace update \
  --resource-group <resource-group> \
  --workspace-name <workspace-name> \
  --retention-time 90
```

## Cost Optimization

- Enable diagnostic sampling to reduce log volume
- Archive older logs to a Storage Account
- Use commitment tiers for predictable workloads
- Filter high-volume, low-value container logs:

```bash
az aks update \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --container-log-v2-enabled true
```

Container log v2 provides structured logs and better filtering options.
