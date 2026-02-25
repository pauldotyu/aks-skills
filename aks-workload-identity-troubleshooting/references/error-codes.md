# Workload Identity Error Codes

## Microsoft Entra ID (AADSTS) Errors

These errors are returned by the Microsoft Entra ID token endpoint during the service account token exchange.

| Error Code      | Name                                                                      | Description                                                                                                                                              | Resolution                                                                                                                                                                                                                                                          |
| --------------- | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AADSTS70021`   | No matching federated identity record                                     | The issuer, subject, or audience in the presented token does not match any federated identity credential configured on the identity or app registration. | Verify the federated credential `issuer` matches the cluster's OIDC issuer URL exactly (including trailing `/`). Verify the `subject` matches `system:serviceaccount:<namespace>:<service-account-name>`. Verify `audiences` contains `api://AzureADTokenExchange`. |
| `AADSTS70011`   | Invalid scope                                                             | The scope (resource) requested in the token exchange is invalid or not recognized.                                                                       | Verify the `scope` parameter in the token request uses a valid resource URI (e.g., `https://management.azure.com/.default`, `https://vault.azure.net/.default`).                                                                                                    |
| `AADSTS700016`  | Application not found                                                     | The application (client ID) specified in the token request was not found in the tenant.                                                                  | Verify the `azure.workload.identity/client-id` annotation on the Kubernetes service account matches the `clientId` of the managed identity or the `appId` of the app registration.                                                                                  |
| `AADSTS700024`  | Client assertion is not within its valid time range                       | The projected service account token has expired or is not yet valid.                                                                                     | Verify the node clock is synchronized. Check that the `service-account-token-expiration` annotation is within the supported range (3600–86400 seconds). Restart the pod to get a fresh token.                                                                       |
| `AADSTS90061`   | Request to External OIDC endpoint failed                                  | Microsoft Entra ID could not reach the cluster's OIDC discovery endpoint to validate the token.                                                          | Run `curl <OIDC_ISSUER_URL>/.well-known/openid-configuration` to verify accessibility. For AKS, reconcile the cluster with `az aks update`. If the issue persists, create an Azure support ticket.                                                                  |
| `AADSTS50020`   | User account from external identity provider does not exist in the tenant | The tenant ID in the token request does not match the tenant where the identity is registered.                                                           | Verify the `azure.workload.identity/tenant-id` annotation on the service account (or the `AZURE_TENANT_ID` environment variable) matches the identity's home tenant.                                                                                                |
| `AADSTS7000215` | Invalid client secret / assertion                                         | The client assertion (projected service account token) is malformed or was tampered with.                                                                | Verify the projected token volume is mounted correctly. Restart the pod. Check that the webhook is injecting the token volume.                                                                                                                                      |

## Common Trailing Slash Issue

A frequent cause of `AADSTS70021` is an issuer URL mismatch due to a trailing slash. AKS OIDC issuer URLs include a trailing `/`:

```
https://oidc.prod-aks.azure.com/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/
```

When creating federated identity credentials, always retrieve the issuer URL directly from the cluster to avoid mismatches:

```bash
az aks show --resource-group <resource-group> --name <cluster-name> \
  --query "oidcIssuerProfile.issuerUrl" -o tsv
```

## Webhook-Related Errors

| Symptom                                               | Likely Cause                                                                   | Resolution                                                                                                                                                 |
| ----------------------------------------------------- | ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pod starts without `AZURE_*` environment variables    | Webhook not running or pod missing `azure.workload.identity/use: "true"` label | Check webhook pods: `kubectl get pods -n kube-system -l app=azure-wi-webhook-webhook-manager`. Add the required label to pod spec.                         |
| Pods fail to start with admission webhook errors      | Webhook certificate expired or webhook is misconfigured                        | Restart the webhook deployment: `kubectl rollout restart deployment azure-wi-webhook-webhook-manager -n kube-system`                                       |
| Token file not found at `$AZURE_FEDERATED_TOKEN_FILE` | Projected volume not mounted                                                   | Verify the pod spec includes the projected service account token volume. Check if the pod was created before the webhook was installed (recreate the pod). |
| `context deadline exceeded` during token exchange     | Network policy or firewall blocking egress to `login.microsoftonline.com`      | Ensure pods can reach `login.microsoftonline.com:443`. Check network policies and NSG rules.                                                               |
