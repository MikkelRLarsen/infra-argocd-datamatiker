# Infisical setup

This checklist matches the current chart values. Actual values stay in Infisical;
do not put passwords or access keys into this document.

## Projects, environments, and paths

Create these projects with the **exact project slugs** below. The display name
can differ. Create/use environment slug **`dev`** in every project; the display
name can be Development. Verify the actual slugs in Infisical settings.

| Project slug | Path | ClusterSecretStore |
| --- | --- | --- |
| `grafana` | `/` | `infisical-grafana-dev` |
| `seaweedfs` | `/` | `infisical-seaweedfs-dev` |
| `loki` | `/secrets` | `infisical-loki-dev` |
| `loki` | `/` | `infisical-loki-dev-root` |
| `prometheus` | `/` | `infisical-prometheus-dev`, `infisical-prometheus` |
| `thanos` | `/` | `infisical-thanos-dev` |
| `bootstrap` | `/` | `infisical-bootstrap-dev` |

Create the `secrets` folder in the Loki project. Every other entry uses the root.
Store declarations live in [external-secrets values](../charts/external-secrets/values.yaml).

## Secrets to create manually

V2 and application passwords below are **plain values**. ESO generates their
ingress htpasswd hashes. The legacy Loki entry is the exception: preserve its
existing complete htpasswd line, including username and hash.

| Project | Path | Infisical secret key | Value and consumer |
| --- | --- | --- | --- |
| `grafana` | `/` | `POSTGRES_PASSWORD` | Grafana PostgreSQL user's password. Preserve the existing database password when retaining its PVC. |
| `grafana` | `/` | `GRAFANA_ADMIN_PASSWORD` | Initial Grafana admin password; username is `admin` in Git. An existing Grafana database may retain its previous login password. |
| `seaweedfs` | `/` | `ADMIN_PASSWORD` | SeaweedFS Admin UI password; username is `admin` in Git. This is separate from S3 credentials. |
| `loki` | `/secrets` | `workload-dev` | Plain Loki v2 ingestion password. Shared by the v2 ingress and Alloy's client Secret. |
| `loki` | `/secrets` | `workload_dev_rw_htpasswd` | Legacy exception: the existing complete `username:password-hash` htpasswd entry, copied unchanged. |
| `loki` | `/secrets` | `workload_dev_rw_password` | Plain legacy client password for Alloy; must match the password hashed in `workload_dev_rw_htpasswd`. Never put the hash in this key. |
| `loki` | `/` | `grafana-dev` | Loki datasource ingress password. Shared by the ingress and Grafana's client Secret. |
| `loki` | `/` | `LOKI_S3_ACCESS_KEY_ID` | Access key for the SeaweedFS `loki` S3 user. |
| `loki` | `/` | `LOKI_S3_SECRET_ACCESS_KEY` | Matching S3 secret key for that user. |
| `prometheus` | `/` | `workload-dev` | Prometheus ingestion ingress password. The ingress remains enabled, although Alloy now sends metrics to Thanos. |
| `prometheus` | `/` | `THANOS_S3_ACCESS_KEY_ID` | Access key for the SeaweedFS `prometheus` S3 user, used by Prometheus's Thanos sidecar. |
| `prometheus` | `/` | `THANOS_S3_SECRET_ACCESS_KEY` | Matching S3 secret key for that user. |
| `thanos` | `/` | `workload-dev` | Thanos ingestion basic-auth password. Shared by Receive's ingress and Alloy's client Secret. |
| `thanos` | `/` | `S3_ACCESS_KEY` | Access key for the SeaweedFS `thanos` S3 user. |
| `thanos` | `/` | `<br/>` | Matching S3 secret key for that user. |

The three `workload-dev` entries are independent keys in separate scopes. They
can have different passwords. Each client and its ingress must read the same key.

There is no Thanos UI password to create. `OBJSTORE_CONFIG`,
`workload_dev_rw_password`, and `UI_ADMIN_PASSWORD` are not used by the current
Thanos configuration. Its non-secret object-store configuration is generated
from [Thanos values](../charts/thanos/values.yaml).

See [SeaweedFS setup](seaweedfs-setup.md) for the matching S3 users and buckets.
Writing an S3 credential into Infisical does not create that user in SeaweedFS.

## ESO machine identity

Create a machine identity with Universal Auth. Grant it read access to all
application projects and paths above, and read/create/update access to
`bootstrap` / `dev` / `/` for PushSecrets. Keep its client ID and client secret.

After Infisical and the `external-secrets` namespace exist, create/update the
one Kubernetes bootstrap credential Secret:

```sh
kubectl -n external-secrets create secret generic infisical-eso-credentials \
  --from-literal=clientId='<client-id>' \
  --from-literal=clientSecret='<client-secret>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

The first command generates YAML; `kubectl apply` actually creates or updates
it. Avoid saving real credential commands in shell history.

## Bootstrap project: populated automatically

Create the project and environment and grant access, but do not seed these keys.
The configured PushSecrets copy Kubernetes values to `bootstrap` / `dev` / `/`.
Kubernetes remains authoritative; `updatePolicy: Replace` overwrites remote edits.

| Infisical key | Kubernetes source (`namespace/Secret`, key) |
| --- | --- |
| `INFISICAL_ENCRYPTION_KEY` | `infisical/infisical-secrets`, `ENCRYPTION_KEY` |
| `INFISICAL_AUTH_SECRET` | `infisical/infisical-secrets`, `AUTH_SECRET` |
| `INFISICAL_POSTGRES_PASSWORD` | `infisical/postgresql`, `password` |
| `INFISICAL_POSTGRES_ADMIN_PASSWORD` | `infisical/postgresql`, `postgres-password` |
| `INFISICAL_REDIS_PASSWORD` | `infisical/redis`, `redis-password` |
| `ESO_CLIENT_ID` | `external-secrets/infisical-eso-credentials`, `clientId` |
| `ESO_CLIENT_SECRET` | `external-secrets/infisical-eso-credentials`, `clientSecret` |
| `ARGOCD_SERVER_SECRET_KEY` | `argocd/argocd-secret`, `server.secretkey` |
| `ARGOCD_ADMIN_PASSWORD_HASH` | `argocd/argocd-secret`, `admin.password` |
| `ARGOCD_ADMIN_PASSWORD_MTIME` | `argocd/argocd-secret`, `admin.passwordMtime` |
| `ARGOCD_REDIS_PASSWORD` | `argocd/argocd-redis`, `auth` |
| `ARGOCD_INITIAL_ADMIN_PASSWORD` | `argocd/argocd-initial-admin-secret`, `password` |

The Argo CD admin hash is copied as a hash; it cannot reveal the plain password.
The initial admin password may no longer be current. Remove its PushSecret source
entry if you deliberately delete `argocd-initial-admin-secret`.

These copies inside Infisical do not replace an independent backup of Infisical's
database and encryption key, and cannot bootstrap ESO before it can authenticate.

## Verify and rotate

```sh
kubectl get clustersecretstores
kubectl get externalsecrets -A
kubectl get pushsecrets -A
```

Stores should become Ready and ExternalSecrets should report successful sync.
Most application secrets refresh every five minutes; Grafana and SeaweedFS admin
secrets refresh every minute. PushSecrets refresh every five minutes.

Ingress authentication follows the refreshed Secret. Environment-variable
consumers need a pod restart to load changed values. Database and S3 account
passwords must also be changed in the service that validates them; ESO alone does
not rotate those accounts. For S3, add a new credential pair in SeaweedFS, update
Infisical, wait for ESO, restart consumers, verify access, then retire the old pair.

## Switching Alloy between Loki legacy and v2

Both client ExternalSecrets are created by k8s-monitoring. Change the two fields
under `k8s-monitoring.destinations.loki-logs` together:

| Route | `url` | `secret.name` |
| --- | --- | --- |
| Legacy | `https://loki.192.168.49.2.nip.io/loki/api/v1/push` | `alloy-remote-write-auth` |
| V2 | `https://loki.192.168.49.2.nip.io/v2/loki/api/v1/push` | `alloy-loki-auth` |

Legacy reads its plain password from `workload_dev_rw_password`; v2 reads its
plain password from `workload-dev`. Both are in `loki` / `dev` / `/secrets`.
The ingress alone reads the complete legacy htpasswd line from
`workload_dev_rw_htpasswd`. Bcrypt cannot be reversed into the client password.

Before switching, sync Loki so both routes exist and check that both client
ExternalSecrets are Ready. Then change and sync the Alloy destination. Keep the
old route and credentials during the transition. This prepares a controlled
cutover; Helm rendering checks alone do not prove zero downtime across clusters.
