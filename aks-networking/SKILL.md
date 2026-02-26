---
name: aks-networking
description: Configure and troubleshoot Azure Kubernetes Service (AKS) networking. Use when setting up or modifying CNI plugins (Azure CNI, kubenet, Azure CNI Overlay, Cilium), configuring ingress controllers (NGINX, Application Gateway), setting up internal or public load balancers, creating or debugging Kubernetes NetworkPolicy or CiliumNetworkPolicy rules, configuring CoreDNS, or diagnosing pod-to-pod, pod-to-service, or external connectivity issues.
---

# AKS Networking

This skill covers AKS networking configuration and troubleshooting, including CNI plugins, load balancers, ingress, network policies, and DNS.

> **Related skills:** For pod/node failures unrelated to networking, see [aks-troubleshooting](../aks-troubleshooting/SKILL.md). For cluster provisioning and upgrades, see [aks-cluster-management](../aks-cluster-management/SKILL.md). For monitoring and alerting, see [aks-monitoring](../aks-monitoring/SKILL.md).

## Network Plugin Options

### Azure CNI (recommended for production)

Pods get IPs from the VNet subnet. Required for Windows node pools and advanced networking features.

```bash
az aks create \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --network-plugin azure \
  --vnet-subnet-id <subnet-id> \
  --service-cidr 10.0.0.0/16 \
  --dns-service-ip 10.0.0.10
```

### Azure CNI Overlay (best for large clusters)

Pods get IPs from an overlay network, not the VNet. Reduces VNet IP consumption significantly.

```bash
az aks create \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --pod-cidr 192.168.0.0/16
```

### kubenet (simple but limited)

Pods use a private IP range with NAT. Does not support Windows nodes or some advanced features.

```bash
az aks create \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --network-plugin kubenet \
  --pod-cidr 10.244.0.0/16
```

## Load Balancers

### Public load balancer (default)

A Standard SKU public load balancer is created automatically when you expose a service of type `LoadBalancer`.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

### Internal load balancer

Use this for services that should only be reachable within the VNet.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-internal-service
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

### Static public IP for a load balancer

```bash
# Create a static IP in the node resource group
NODE_RG=$(az aks show \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --query "nodeResourceGroup" -o tsv)

az network public-ip create \
  --resource-group "$NODE_RG" \
  --name my-static-ip \
  --sku Standard \
  --allocation-method static
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-resource-group: "<node-resource-group>"
    # Preferred: use this annotation instead of spec.loadBalancerIP (deprecated in K8s 1.24)
    service.beta.kubernetes.io/azure-load-balancer-ipv4: "<static-ip-address>"
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

## Ingress

### NGINX Ingress Controller (Helm)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.replicaCount=2
```

Basic ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-service
                port:
                  number: 80
```

### Application Gateway Ingress Controller (AGIC)

Enable via the AKS add-on:

```bash
az aks enable-addons \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --addons ingress-appgw \
  --appgw-name <app-gateway-name> \
  --appgw-subnet-cidr 10.225.0.0/16
```

## Network Policies

Network policies require a compatible CNI plugin (`--network-policy azure` or `--network-policy calico`). Clusters using **Azure CNI powered by Cilium** (`--network-dataplane cilium`) enforce both standard Kubernetes `NetworkPolicy` and Cilium-specific `CiliumNetworkPolicy` / `CiliumClusterwideNetworkPolicy` resources.

### Deny all ingress by default, then allow selectively

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

### Allow ingress from a specific namespace

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-monitoring
  namespace: <namespace>
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: monitoring
```

### CiliumNetworkPolicy (Azure CNI powered by Cilium)

On AKS clusters with `--network-dataplane cilium`, you can use `CiliumNetworkPolicy` for L3-L7 policy enforcement with richer matching (DNS-based egress, HTTP-aware rules, etc.). These policies are additive — Cilium enforces both standard `NetworkPolicy` and `CiliumNetworkPolicy` simultaneously.

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-http-from-frontend
  namespace: <namespace>
spec:
  endpointSelector:
    matchLabels:
      app: my-api
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
          rules:
            http:
              - method: GET
                path: /api/.*
```

Cluster-wide policies use `CiliumClusterwideNetworkPolicy` (no namespace):

```yaml
apiVersion: cilium.io/v2
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: deny-external-egress
spec:
  endpointSelector: {}
  egressDeny:
    - toEntities:
        - world
```

DNS-based egress policy (allow traffic only to specific FQDNs):

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-egress-to-api
  namespace: <namespace>
spec:
  endpointSelector:
    matchLabels:
      app: my-app
  egress:
    - toEndpoints:
        - matchLabels:
            k8s:io.kubernetes.pod.namespace: kube-system
            k8s-app: kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: ANY
          rules:
            dns:
              - matchPattern: "*.example.com"
    - toFQDNs:
        - matchPattern: "*.example.com"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
```

## DNS Configuration

AKS uses CoreDNS for cluster DNS. Check CoreDNS status:

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### Custom CoreDNS configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  example.server: |
    example.com:53 {
        forward . 1.2.3.4
    }
```

```bash
kubectl apply -f coredns-custom.yaml
kubectl rollout restart deployment coredns -n kube-system
```

## Troubleshooting Connectivity

For step-by-step connectivity troubleshooting (pod health, services/endpoints, network policies, in-cluster tests, DNS, ingress, kube-proxy/CNI, and Azure-level diagnostics), see [references/troubleshooting-connectivity.md](references/troubleshooting-connectivity.md).

## References

- [AKS networking concepts](./references/networking-concepts.md)
- [Troubleshooting connectivity](./references/troubleshooting-connectivity.md)
- [Azure CNI documentation](https://learn.microsoft.com/en-us/azure/aks/configure-azure-cni)
- [Azure network policies](https://learn.microsoft.com/en-us/azure/aks/use-network-policies)
- [AKS ingress documentation](https://learn.microsoft.com/en-us/azure/aks/ingress-basic)
