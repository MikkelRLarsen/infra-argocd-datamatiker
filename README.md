# infra-argocd-datamatiker

GitOps repo for a local minikube cluster, managed by Argo CD. Any machine can
rebuild the same cluster from this repo.

## Bootstrap

```bash
./bootstrap/install.sh
```

This starts minikube (if it isn't running), installs Argo CD with Helm from
`charts/argocd`, and applies the root ApplicationSet. It prints the admin
password and how to open the UI when done.

Override minikube resources with `MINIKUBE_CPUS` / `MINIKUBE_MEMORY` (MB).

## Self-managed Argo CD

`apps/argocd` deploys `charts/argocd` with release name `argocd` — the same chart
and values `install.sh` installs — so Argo CD adopts its own install. To change
Argo CD (version or config), edit `charts/argocd` and push. It syncs
automatically but never prunes, and deleting the Application does not delete
Argo CD.

## Grafana with PostgreSQL

`apps/grafana` deploys Grafana and a single PostgreSQL instance in the `grafana`
namespace. PostgreSQL stores Grafana's users, dashboards, and settings (it is
not provisioned as a dashboard data source). Its 5Gi PVC uses the cluster's
default storage class and is retained when the StatefulSet is deleted.

Before pushing/syncing the application, create credentials once:

```bash
kubectl create namespace grafana
kubectl -n grafana create secret generic grafana-credentials \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$(openssl rand -hex 24)" \
  --from-literal=postgres-password="$(openssl rand -hex 24)"
```

Keep this Secret when reusing the database PVC. Changing its password does not
change the password inside an initialized PostgreSQL database; rotate both
together. Back up the database and Secret if the cluster needs to be rebuilt.

After pushing to `main` and allowing Argo CD to sync:

```bash
kubectl -n grafana rollout status deployment/grafana
kubectl -n grafana get secret grafana-credentials \
  -o jsonpath='{.data.admin-password}' | base64 --decode; echo
kubectl -n grafana port-forward svc/grafana 3000:80
```

Open http://localhost:3000 and sign in as `admin` with the retrieved password.
This deployment targets local minikube: PostgreSQL uses internal plaintext
connections, and Grafana is exposed through port-forwarding only.

To validate locally:

```bash
helm dependency build charts/grafana
helm lint charts/grafana
helm template grafana charts/grafana --namespace grafana > /tmp/grafana.yaml
```

## Infisical and External Secrets Operator

`apps/infisical` deploys Infisical with bundled PostgreSQL and Redis in the
`infisical` namespace. `apps/external-secrets` installs ESO and its CRDs in the
`external-secrets` namespace; ESO is a separate install, not bundled with Infisical.
Both are discovered automatically by the root ApplicationSet.

Before syncing Infisical, create its application keys once:

```bash
kubectl create namespace infisical
kubectl -n infisical create secret generic infisical-secrets \
  --from-literal=ENCRYPTION_KEY="$(openssl rand -hex 16)" \
  --from-literal=AUTH_SECRET="$(openssl rand -hex 32)" \
  --from-literal=SITE_URL=http://localhost:8080
```

Keep this Secret and the database PVC when reusing the installation; Infisical
needs the same encryption key to decrypt stored secrets. This local setup uses
the upstream chart's development PostgreSQL and Redis passwords and exposes no
ingress. Open the UI after syncing:

```bash
kubectl -n infisical port-forward svc/infisical 8080:8080
```

Visit http://localhost:8080 to create your account and project. ESO still needs
a `SecretStore` or `ClusterSecretStore` with Infisical machine identity credentials
and an `ExternalSecret` for each secret to sync. Those depend on the project you
create; installing the charts alone does not sync application credentials.
See the [ESO Infisical provider documentation](https://external-secrets.io/latest/provider/infisical/).

## Layout

```
bootstrap/
  install.sh           one-time setup of a fresh cluster
  root-appset.yaml     root ApplicationSet: one Application per apps/<svc>/
apps/<svc>/            Argo CD Application for the service (application.yaml)
charts/<svc>/          the service's Helm chart (umbrella chart + values.yaml)
```

## Adding an app

1. Create `charts/<svc>/` with `Chart.yaml` (upstream chart under
   `dependencies:`) and `values.yaml`.
2. Create `apps/<svc>/application.yaml` pointing at `charts/<svc>`.
3. Push to `main` — Argo CD picks it up automatically.

Example `apps/<svc>/application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <svc>
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/MikkelRLarsen/infra-argocd-datamatiker.git
    targetRevision: main
    path: charts/<svc>
    helm:
      releaseName: <svc>
      valueFiles: [values.yaml]
  destination:
    server: https://kubernetes.default.svc
    namespace: <svc>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```
