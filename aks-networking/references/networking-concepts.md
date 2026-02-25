# AKS Networking Concepts

## IP Address Planning

Plan IP ranges carefully before creating a cluster. Ranges cannot be changed after creation.

| Network | Recommended Range | Notes |
|---------|-------------------|-------|
| VNet | /8 to /16 | Large enough for all subnets |
| Node subnet | /24 or larger | Each node needs 1 IP (Azure CNI) or fewer (Overlay) |
| Service CIDR | /16 | Cannot overlap with VNet or pod CIDR |
| Pod CIDR | /16 (Overlay) or N/A | Only for Overlay/kubenet; cannot overlap with VNet |
| DNS service IP | Single IP | Must be within service CIDR range |

## CNI Comparison

| Feature | kubenet | Azure CNI | Azure CNI Overlay |
|---------|---------|-----------|-------------------|
| VNet IP usage | Low (only nodes) | High (nodes + pods) | Low (only nodes) |
| Windows nodes | ❌ | ✅ | ✅ |
| Network policy | Calico only | Azure or Calico | Azure or Calico |
| Performance | Good | Better | Better |
| IP planning complexity | Low | High | Low |
| Max pods per node | 110 | 250 (default 30) | 250 |

## Load Balancer SKUs

AKS requires Standard SKU load balancers. Basic SKU is not supported.

- **Standard**: Required for AKS; supports availability zones, cross-region LB, multiple frontends
- **Basic**: Not supported in AKS

## Service Types

| Type | Use Case |
|------|----------|
| `ClusterIP` | Internal access only (default) |
| `NodePort` | Exposes service on each node's IP at a static port |
| `LoadBalancer` | Creates an Azure load balancer with a public or internal IP |
| `ExternalName` | Maps service to a DNS name |

## Ingress vs. Service LoadBalancer

| | Service LoadBalancer | Ingress |
|-|---------------------|---------|
| Works at | L4 (TCP/UDP) | L7 (HTTP/HTTPS) |
| SSL termination | ❌ (by default) | ✅ |
| Path-based routing | ❌ | ✅ |
| Host-based routing | ❌ | ✅ |
| Azure resource | Azure Load Balancer | App Gateway or NIC-hosted |
| Cost | 1 public IP per service | 1 IP shared across many services |

## Common Port Numbers

| Service | Port |
|---------|------|
| Kubernetes API server | 443 |
| kubelet | 10250 |
| CoreDNS | 53 (UDP/TCP) |
| NodePort range | 30000-32767 |
| Metrics server | 4443 |

## Private Cluster Networking

In a private cluster, the API server endpoint is only accessible via private link.

- Requires a private DNS zone linked to the VNet
- `kubectl` must run from within the VNet or a connected network (VPN/ExpressRoute/peering)
- Use `--private-cluster-enabled` at create time
- Cannot be changed after cluster creation
