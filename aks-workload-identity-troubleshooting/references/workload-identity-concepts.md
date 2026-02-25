# Workload Identity Concepts

## How It Works

AKS workload identity uses the OIDC federation protocol:

1. The AKS cluster acts as a **token issuer** via its OIDC issuer endpoint.
2. A Kubernetes **projected service account token** is mounted into the pod.
3. The pod presents this token to Microsoft Entra ID, which validates it against the cluster's OIDC discovery endpoint.
4. Microsoft Entra ID exchanges the Kubernetes token for a **Microsoft Entra access token**.
5. The workload uses the Microsoft Entra token to access Azure resources.

### OIDC Endpoints

| Endpoint                                       | Purpose                                                                            |
| ---------------------------------------------- | ---------------------------------------------------------------------------------- |
| `{IssuerURL}/.well-known/openid-configuration` | OIDC discovery document with issuer metadata                                       |
| `{IssuerURL}/openid/v1/jwks`                   | Public signing keys used by Microsoft Entra ID to verify the service account token |

## Environment Variables Injected by the Webhook

When a pod has the label `azure.workload.identity/use: "true"`, the mutating admission webhook injects these environment variables:

| Variable                     | Source                                                                                                | Description                                                                                                       |
| ---------------------------- | ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `AZURE_CLIENT_ID`            | Service account annotation `azure.workload.identity/client-id`                                        | Client ID of the managed identity or app registration                                                             |
| `AZURE_TENANT_ID`            | Service account annotation `azure.workload.identity/tenant-id` or `azure-wi-webhook-config` ConfigMap | Microsoft Entra tenant ID                                                                                         |
| `AZURE_FEDERATED_TOKEN_FILE` | Projected volume path                                                                                 | Path to the projected service account token file (typically `/var/run/secrets/azure/tokens/azure-identity-token`) |
| `AZURE_AUTHORITY_HOST`       | `azure-wi-webhook-config` ConfigMap                                                                   | Microsoft Entra authority URL (e.g., `https://login.microsoftonline.com/`)                                        |

## Service Account Annotations

| Annotation                                                 | Required | Default                                  | Description                                        |
| ---------------------------------------------------------- | -------- | ---------------------------------------- | -------------------------------------------------- |
| `azure.workload.identity/client-id`                        | Yes      | —                                        | Client ID of the identity the pod authenticates as |
| `azure.workload.identity/tenant-id`                        | No       | From `azure-wi-webhook-config` ConfigMap | Tenant ID where the identity is registered         |
| `azure.workload.identity/service-account-token-expiration` | No       | `3600`                                   | Token expiration in seconds (range: 3600–86400)    |

## Pod Labels

| Label                         | Required       | Description                                                                    |
| ----------------------------- | -------------- | ------------------------------------------------------------------------------ |
| `azure.workload.identity/use` | Yes (`"true"`) | Must be on the pod (not just the service account) for the webhook to mutate it |

## Pod Annotations

| Annotation                                                 | Default | Description                                                                                          |
| ---------------------------------------------------------- | ------- | ---------------------------------------------------------------------------------------------------- |
| `azure.workload.identity/service-account-token-expiration` | `3600`  | Overrides the service account annotation if set                                                      |
| `azure.workload.identity/skip-containers`                  | —       | Semi-colon-separated list of container names to skip token injection                                 |
| `azure.workload.identity/inject-proxy-sidecar`             | `false` | Inject a proxy sidecar that intercepts IMDS token requests (for migration from pod-managed identity) |
| `azure.workload.identity/proxy-sidecar-port`               | `8000`  | Port used by the proxy sidecar                                                                       |

## Federated Identity Credential Fields

| Field       | Expected Value                                             | Notes                                                                        |
| ----------- | ---------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `issuer`    | Cluster OIDC issuer URL                                    | Must match exactly, including trailing `/`                                   |
| `subject`   | `system:serviceaccount:<namespace>:<service-account-name>` | Case-sensitive; must match the Kubernetes namespace and service account name |
| `audiences` | `api://AzureADTokenExchange`                               | Default audience; do not change unless using a custom configuration          |

### Limits

- Maximum **20 federated identity credentials** per managed identity.
- Federated credentials may take **a few seconds to propagate** after creation.
- Virtual nodes (ACI-based) are **not supported**.

## Azure Identity SDK Minimum Versions

Use `DefaultAzureCredential` or `WorkloadIdentityCredential` from the Azure Identity client library:

| Language | Package              | Minimum Version |
| -------- | -------------------- | --------------- |
| .NET     | `Azure.Identity`     | 1.9.0           |
| C++      | `azure-identity-cpp` | 1.6.0           |
| Go       | `azidentity`         | 1.3.0           |
| Java     | `azure-identity`     | 1.9.0           |
| Node.js  | `@azure/identity`    | 3.2.0           |
| Python   | `azure-identity`     | 1.13.0          |

## Identity Mapping Patterns

Workload identity supports flexible mapping between Kubernetes service accounts and Microsoft Entra identities:

| Pattern         | Description                                                                                               |
| --------------- | --------------------------------------------------------------------------------------------------------- |
| **One-to-one**  | One service account references one Microsoft Entra identity                                               |
| **Many-to-one** | Multiple service accounts reference the same Microsoft Entra identity                                     |
| **One-to-many** | One service account references multiple Microsoft Entra identities by changing the `client-id` annotation |

## External References

- [Use Microsoft Entra Workload ID with AKS](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [Deploy and configure workload identity on AKS](https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster)
- [Migrate from pod-managed identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-migrate-from-pod-identity)
- [azure-workload-identity GitHub (troubleshooting)](https://azure.github.io/azure-workload-identity/docs/troubleshooting.html)
- [Federated identity credential considerations](https://learn.microsoft.com/en-us/azure/active-directory/workload-identities/workload-identity-federation-considerations)
