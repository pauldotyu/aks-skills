---
name: aks-workload-identity
description: Configure and troubleshoot Microsoft Entra Workload ID on Azure Kubernetes Service (AKS). Use when enabling OIDC issuer and workload identity on a cluster, creating user-assigned managed identities or Microsoft Entra ID app registrations with federated credentials, setting up Kubernetes service accounts for workload identity, deploying pods that authenticate to Azure services without secrets, diagnosing AADSTS token exchange errors (AADSTS70021, AADSTS700016, AADSTS700024), or resolving webhook mutation issues.
---

# AKS Workload Identity

Microsoft Entra Workload ID allows pods running on AKS to authenticate to Azure services without storing secrets or API keys. It uses the OpenID Connect (OIDC) federation protocol to exchange a Kubernetes service account token for a Microsoft Entra access token.

This skill covers end-to-end **configuration** and **troubleshooting** of workload identity on AKS.

See [./references/workload-identity-concepts.md](./references/workload-identity-concepts.md) for environment variables, annotations, labels, SDK versions, and federated credential field requirements. See [./references/error-codes.md](./references/error-codes.md) for detailed AADSTS error codes and webhook-related errors.

## Prerequisites

- Azure CLI 2.47.0+ installed and authenticated (`az login`)
- `kubectl` connected to the target AKS cluster (`az aks get-credentials`)
- Sufficient permissions to create managed identities and role assignments (Contributor + Managed Identity Operator on the resource group)

## Configuration

### Step 1: Enable OIDC Issuer and Workload Identity on the AKS Cluster

**New cluster:**

```bash
az aks create \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --generate-ssh-keys
```

**Existing cluster:**

```bash
az aks update \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --enable-oidc-issuer \
  --enable-workload-identity
```

Verify both features are enabled:

```bash
az aks show --resource-group <resource-group> --name <cluster-name> \
  --query "{oidcIssuerEnabled: oidcIssuerProfile.enabled, workloadIdentityEnabled: securityProfile.workloadIdentity.enabled}"
```

Both values must be `true`.

### Step 2: Retrieve the OIDC Issuer URL

```bash
export AKS_OIDC_ISSUER="$(az aks show \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --query "oidcIssuerProfile.issuerUrl" \
  --output tsv)"
```

> **Important:** Always retrieve the issuer URL directly from the cluster. The URL includes a trailing `/` and must match exactly in federated credentials.

### Step 3: Create an Azure Identity

Workload identity supports two identity types:

**Option A — User-Assigned Managed Identity (recommended):**

```bash
az identity create \
  --name <identity-name> \
  --resource-group <resource-group> \
  --location <location>

export USER_ASSIGNED_CLIENT_ID="$(az identity show \
  --resource-group <resource-group> \
  --name <identity-name> \
  --query 'clientId' \
  --output tsv)"
```

**Option B — Microsoft Entra ID App Registration:**

```bash
az ad app create --display-name <app-name>
az ad sp create --id <app-id>

export USER_ASSIGNED_CLIENT_ID="<app-id>"
```

### Step 4: Create a Kubernetes Service Account

```bash
export SERVICE_ACCOUNT_NAMESPACE="<namespace>"
export SERVICE_ACCOUNT_NAME="<service-account-name>"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "${USER_ASSIGNED_CLIENT_ID}"
  name: "${SERVICE_ACCOUNT_NAME}"
  namespace: "${SERVICE_ACCOUNT_NAMESPACE}"
EOF
```

The `azure.workload.identity/client-id` annotation is required. Optionally add `azure.workload.identity/tenant-id` if the identity is in a different tenant.

### Step 5: Create the Federated Identity Credential

**For User-Assigned Managed Identity:**

```bash
az identity federated-credential create \
  --name <credential-name> \
  --identity-name <identity-name> \
  --resource-group <resource-group> \
  --issuer "${AKS_OIDC_ISSUER}" \
  --subject system:serviceaccount:"${SERVICE_ACCOUNT_NAMESPACE}":"${SERVICE_ACCOUNT_NAME}" \
  --audience api://AzureADTokenExchange
```

**For Microsoft Entra ID App Registration:**

```bash
az ad app federated-credential create --id <app-id> --parameters '{
  "name": "<credential-name>",
  "issuer": "'"${AKS_OIDC_ISSUER}"'",
  "subject": "system:serviceaccount:'"${SERVICE_ACCOUNT_NAMESPACE}"':'"${SERVICE_ACCOUNT_NAME}"'",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

> **Note:** Federated credentials may take a few seconds to propagate. If a token request fails immediately after creation, wait and retry.

### Step 6: Assign Azure RBAC Roles to the Identity

Grant the identity the minimum required permissions on the Azure resource it needs to access:

```bash
# Get the principal ID of the managed identity
export IDENTITY_PRINCIPAL_ID=$(az identity show \
  --name <identity-name> \
  --resource-group <resource-group> \
  --query principalId \
  --output tsv)

# Assign a role (example: Key Vault Secrets User)
az role assignment create \
  --assignee-object-id "${IDENTITY_PRINCIPAL_ID}" \
  --role "<role-name>" \
  --scope "<resource-id>" \
  --assignee-principal-type ServicePrincipal
```

Common role assignments:

| Azure Service     | Role                           | Scope                      |
| ----------------- | ------------------------------ | -------------------------- |
| Key Vault secrets | Key Vault Secrets User         | Key vault resource ID      |
| Key Vault keys    | Key Vault Crypto User          | Key vault resource ID      |
| Storage (blobs)   | Storage Blob Data Contributor  | Storage account/container  |
| Azure OpenAI      | Cognitive Services OpenAI User | Cognitive Services account |
| Azure SQL         | N/A (use Entra authentication) | N/A                        |

> **Important:** Azure RBAC role assignments can take up to 10 minutes to propagate.

### Step 7: Deploy a Workload Using the Identity

The pod template **must** include the `azure.workload.identity/use: "true"` label and reference the service account:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <deployment-name>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <app-name>
  template:
    metadata:
      labels:
        app: <app-name>
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: <service-account-name>
      nodeSelector:
        kubernetes.io/os: linux
      containers:
        - name: <container-name>
          image: <image>
```

The mutating admission webhook automatically injects:

- `AZURE_CLIENT_ID` — from the service account annotation
- `AZURE_TENANT_ID` — from the webhook config or service account annotation
- `AZURE_FEDERATED_TOKEN_FILE` — path to the projected service account token
- `AZURE_AUTHORITY_HOST` — Microsoft Entra authority URL

### Step 8: Use Azure Identity SDK in Application Code

Use `DefaultAzureCredential` or `WorkloadIdentityCredential` from the Azure Identity client library. The SDK automatically reads the injected environment variables.

**Python example:**

```python
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

credential = DefaultAzureCredential()
client = SecretClient(vault_url="https://<vault-name>.vault.azure.net", credential=credential)
secret = client.get_secret("<secret-name>")
```

**Go example:**

```go
cred, err := azidentity.NewDefaultAzureCredential(nil)
```

**Node.js example:**

```javascript
const { DefaultAzureCredential } = require("@azure/identity");
const credential = new DefaultAzureCredential();
```

See [./references/workload-identity-concepts.md](./references/workload-identity-concepts.md) for minimum SDK versions per language.

## Troubleshooting

### 1. Verify Cluster Configuration

```bash
az aks show --resource-group <resource-group> --name <cluster-name> \
  --query "{oidcIssuerEnabled: oidcIssuerProfile.enabled, workloadIdentityEnabled: securityProfile.workloadIdentity.enabled}"
```

Both values must be `true`. If not, enable them with `az aks update --enable-oidc-issuer --enable-workload-identity`.

### 2. Verify the Managed Identity or App Registration

Confirm the Azure identity resource exists and note its `clientId` and `principalId`. This step is critical for pinpointing which Azure identity provides workload identity so subsequent troubleshooting can target the correct resource.

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

### 3. Verify Federated Identity Credentials

**For User-Assigned Managed Identity:**

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

- **`issuer`** matches the cluster's OIDC issuer URL exactly (including trailing `/`).
- **`subject`** matches `system:serviceaccount:<namespace>:<service-account-name>` (case-sensitive).
- **`audiences`** contains `api://AzureADTokenExchange`.

### 4. Verify the Kubernetes Service Account

```bash
kubectl get serviceaccount <service-account-name> -n <namespace> -o yaml
```

Confirm the `azure.workload.identity/client-id` annotation is present and matches the identity's `clientId` (managed identity) or `appId` (app registration) from step 2.

### 5. Verify Pod Labels and Webhook Injection

```bash
kubectl get pod <pod-name> -n <namespace> -o yaml
```

Check for:

- Label `azure.workload.identity/use: "true"` on the pod (not just the deployment)
- Environment variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_FEDERATED_TOKEN_FILE`
- A projected volume of type `serviceAccountToken` with audience `api://AzureADTokenExchange`

To inspect the projected volumes directly:

```bash
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.volumes}' | jq
```

> **Note:** The token file path varies by webhook version. The open-source webhook mounts at `/var/run/secrets/azure/tokens/azure-identity-token`, while the AKS-managed webhook `v1.6.0-alpha.1`+ mounts at `/var/run/secrets/azure/wi/token/azure-identity-token`. Always use the `$AZURE_FEDERATED_TOKEN_FILE` environment variable rather than hardcoding the path.

### 6. Check the Mutating Admission Webhook

```bash
kubectl get pods -n kube-system -l app=azure-wi-webhook-webhook-manager
kubectl get mutatingwebhookconfiguration azure-wi-webhook-webhook-configuration
```

If the webhook pods are not running, restart them:

```bash
kubectl rollout restart deployment azure-wi-webhook-webhook-manager -n kube-system
```

### 7. Check RBAC Permissions

```bash
az role assignment list --assignee <client-id-or-principal-id> -o table
```

Verify the identity has the required role on the target Azure resource.

### 8. Check Application Logs

```bash
kubectl logs <pod-name> -n <namespace>
```

Common error patterns:

| Error Code      | Meaning                               | Fix                                                                 |
| --------------- | ------------------------------------- | ------------------------------------------------------------------- |
| `AADSTS70021`   | No matching federated identity record | Verify issuer, subject, and audience in the federated credential    |
| `AADSTS700016`  | Application not found                 | Verify client ID in service account annotation matches the identity |
| `AADSTS700024`  | Token expired or not yet valid        | Sync node clock; check token expiration annotation; restart pod     |
| `AADSTS70011`   | Invalid scope                         | Verify the resource URI in the token request                        |
| `AADSTS7000215` | Invalid client assertion              | Verify projected token volume is mounted; restart pod               |

See [./references/error-codes.md](./references/error-codes.md) for the full error reference.

### 9. Validate Token Exchange Manually

```bash
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
# Inside the pod:
cat $AZURE_FEDERATED_TOKEN_FILE
curl -s -X POST "https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=<client-id>" \
  -d "client_assertion=$(cat $AZURE_FEDERATED_TOKEN_FILE)" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "scope=https://management.azure.com/.default"
```

## Common Misconfigurations

| Issue                                      | Likely Cause                                                                                                               |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `AADSTS70021` token exchange failure       | Federated credential `issuer`, `subject`, or `audience` mismatch                                                           |
| Pod not mutated (missing env vars)         | Missing `azure.workload.identity/use: "true"` label on pod template                                                        |
| Service account token not projected        | Webhook not running or pod created before webhook was installed                                                            |
| Token path mismatch / hardcoded path fails | AKS-managed webhook `v1.6.0-alpha.1`+ uses a different mount path; use `$AZURE_FEDERATED_TOKEN_FILE` instead of hardcoding |
| Permission denied on Azure resource        | Missing RBAC role assignment for the managed identity or service principal                                                 |
| Client ID not found                        | `azure.workload.identity/client-id` annotation missing or incorrect on service account                                     |
| Auth fails immediately after setup         | Federated credential propagation delay; wait a few seconds and retry                                                       |
| RBAC role assigned but access denied       | RBAC propagation delay (up to 10 minutes); wait and retry                                                                  |

## Disabling Workload Identity

To disable Microsoft Entra Workload ID on an AKS cluster:

```bash
az aks update \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --disable-workload-identity
```

> **Warning:** This disables the webhook for all pods in the cluster. Pods relying on workload identity will lose the ability to authenticate.
