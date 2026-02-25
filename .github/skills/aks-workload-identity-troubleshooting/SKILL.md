---
name: aks-workload-identity-troubleshooting
description: Guide for troubleshooting workload identity configuration in Azure Kubernetes Service (AKS). Use this when asked to troubleshoot or diagnose workload identity issues in AKS clusters.
---

# AKS Workload Identity Troubleshooting

Workload identity in AKS allows pods to authenticate to Azure services without storing credentials. It can be implemented using:

- **Azure User-Assigned Managed Identity** – a standalone Azure resource that can be assigned to AKS pods.
- **Microsoft Entra ID App Registration** – an application identity registered in Microsoft Entra ID (formerly Azure Active Directory).

Both options support **federated identity credentials**, which allow a Kubernetes service account token to be exchanged for an Azure access token via the OpenID Connect (OIDC) protocol.

## Prerequisites

Before troubleshooting, verify the following are configured on the AKS cluster:

1. **OIDC Issuer** is enabled on the cluster.
2. **Workload Identity** add-on is enabled on the cluster.

## Troubleshooting Steps

### 1. Verify Cluster Configuration

Check that the OIDC issuer URL and workload identity are enabled:

```bash
az aks show --resource-group <resource-group> --name <cluster-name> \
  --query "{oidcIssuerEnabled: oidcIssuerProfile.enabled, workloadIdentityEnabled: securityProfile.workloadIdentity.enabled}"
```

Both values should be `true`.

### 2. Retrieve the OIDC Issuer URL

```bash
az aks show --resource-group <resource-group> --name <cluster-name> \
  --query "oidcIssuerProfile.issuerUrl" -o tsv
```

### 3. Verify the Managed Identity or App Registration

**For Azure User-Assigned Managed Identity:**

```bash
az identity show --resource-group <resource-group> --name <identity-name>
```

Note the `clientId` and `principalId` from the output.

**For Microsoft Entra ID App Registration:**

```bash
az ad app show --id <app-id>
az ad sp show --id <app-id>
```

Note the `appId` (client ID) and the associated service principal `id`.

### 4. Verify Federated Identity Credentials

**For Azure User-Assigned Managed Identity:**

```bash
az identity federated-credential list \
  --identity-name <identity-name> \
  --resource-group <resource-group>
```

**For Microsoft Entra ID App Registration:**

```bash
az ad app federated-credential list --id <app-id>
```

For each federated credential, confirm:

- **`issuer`** matches the cluster's OIDC issuer URL exactly.
- **`subject`** matches the format: `system:serviceaccount:<namespace>:<service-account-name>`
- **`audiences`** contains `api://AzureADTokenExchange`

### 5. Verify the Kubernetes Service Account

Check that the service account exists and has the correct annotations:

```bash
kubectl get serviceaccount <service-account-name> -n <namespace> -o yaml
```

Expected annotations:

```yaml
annotations:
  azure.workload.identity/client-id: <client-id-of-identity-or-app>
```

Optionally, the `azure.workload.identity/tenant-id` annotation may also be present.

### 6. Verify Pod Labels and Annotations

Check that the pod (or its pod template) has the workload identity label:

```bash
kubectl get pod <pod-name> -n <namespace> -o yaml
```

Expected label:

```yaml
labels:
  azure.workload.identity/use: "true"
```

### 7. Verify Projected Service Account Token

Pods using workload identity should have a projected volume for the service account token:

```bash
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.volumes}'
```

Look for a `projected` volume of type `serviceAccountToken` with the audience `api://AzureADTokenExchange`.

### 8. Check the Mutating Admission Webhook

The workload identity mutating admission webhook (`azure-wi-webhook-*`) should be running in the `kube-system` namespace:

```bash
kubectl get pods -n kube-system -l app=azure-wi-webhook-webhook-manager
kubectl get mutatingwebhookconfiguration azure-wi-webhook-webhook-configuration
```

If the webhook pods are not running, restart them:

```bash
kubectl rollout restart deployment azure-wi-webhook-webhook-manager -n kube-system
```

### 9. Check RBAC Permissions

Ensure the managed identity or service principal has the necessary Azure RBAC role assignments for the resources it needs to access:

```bash
az role assignment list --assignee <client-id-or-principal-id> -o table
```

### 10. Check Application Logs

Review logs for authentication errors:

```bash
kubectl logs <pod-name> -n <namespace>
```

Common error patterns to look for:

- `AADSTS70021` – No matching federated identity record found. Verify the issuer, subject, and audience in the federated credential.
- `AADSTS70011` – Invalid scope. Verify the resource URI in the token request.
- `AADSTS700016` – Application not found. Verify the client ID in the service account annotation.

### 11. Validate Token Exchange Manually

To test the token exchange manually inside the pod:

```bash
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
# Inside the pod:
cat $AZURE_FEDERATED_TOKEN_FILE
curl -s -X POST "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
  -d "client_id=<client-id>" \
  -d "client_assertion=$(cat $AZURE_FEDERATED_TOKEN_FILE)" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "scope=https://management.azure.com/.default"
```

## Common Misconfigurations

| Issue | Likely Cause |
|---|---|
| `AADSTS70021` token exchange failure | Federated credential `issuer`, `subject`, or `audience` mismatch |
| Pod not mutated (missing env vars) | Missing `azure.workload.identity/use: "true"` label on pod |
| Service account token not projected | Webhook not running or pod created before webhook was installed |
| Permission denied on Azure resource | Missing RBAC role assignment for the managed identity or service principal |
| Client ID not found | `azure.workload.identity/client-id` annotation missing or incorrect on service account |
