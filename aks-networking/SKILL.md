---
name: aks-networking
description: Configure and troubleshoot Azure Kubernetes Service (AKS) networking. Use when setting up or modifying CNI plugins (Azure CNI, kubenet, Azure CNI Overlay), configuring ingress controllers (NGINX, Application Gateway Ingress Controller), setting up internal or external load balancers, managing network policies, configuring DNS, or diagnosing connectivity issues between pods, services, or external endpoints.
license: MIT
metadata:
  author: pauldotyu
  version: "1.0"
compatibility: Requires kubectl connected to the target cluster and az CLI with an authenticated Azure session
---

# AKS Networking

This skill covers AKS networking configuration and troubleshooting, including CNI plugins, load balancers, ingress, network policies, and DNS.

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

Network policies require a compatible CNI plugin (`--network-policy azure` or `--network-policy calico`).

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

### Test pod-to-pod connectivity

```bash
kubectl run netshoot --image=nicolaka/netshoot --rm -it -- bash
# Inside:
# curl http://<pod-ip>:<port>
# ping <pod-ip>
```

### Check service endpoints

```bash
kubectl get endpoints <service-name> -n <namespace>
```

If endpoints are empty, the service selector does not match any pod labels.

### Trace DNS resolution

```bash
kubectl run dnstest --image=busybox:1.28 --rm -it -- sh
# Inside:
# nslookup <service-name>.<namespace>.svc.cluster.local
# nslookup <external-hostname>
```

### Check effective network policies for a pod

```bash
kubectl get networkpolicies -n <namespace>
```

Use `networkpolicy-viewer` or similar tools for visualizing policies.

## References

- [AKS networking concepts](references/networking-concepts.md)
- [Azure CNI documentation](https://learn.microsoft.com/en-us/azure/aks/configure-azure-cni)
- [Azure network policies](https://learn.microsoft.com/en-us/azure/aks/use-network-policies)
- [AKS ingress documentation](https://learn.microsoft.com/en-us/azure/aks/ingress-basic)
