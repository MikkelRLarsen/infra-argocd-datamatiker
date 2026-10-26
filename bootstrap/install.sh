#!/usr/bin/env bash
# Bootstrap a fresh minikube cluster with Argo CD and point it at this repo.
# Safe to re-run: every step is idempotent.
#
# Argo CD is installed from charts/argocd — the same chart + values that
# apps/argocd/application.yaml deploys — so Argo CD adopts this install and
# manages itself afterwards. Version and values live only in charts/argocd.
set -euo pipefail

MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-8192}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGOCD_CHART="$REPO_ROOT/charts/argocd"

for cmd in minikube kubectl helm; do
  command -v "$cmd" >/dev/null || { echo "missing required tool: $cmd" >&2; exit 1; }
done

if ! minikube status >/dev/null 2>&1; then
  echo "==> Starting minikube"
  minikube start --cpus="$MINIKUBE_CPUS" --memory="$MINIKUBE_MEMORY"
fi
kubectl config use-context minikube >/dev/null

MINIKUBE_IP="$(minikube ip)"
INFISICAL_HOST="infisical.${MINIKUBE_IP}.nip.io"
INFISICAL_SITE_URL="http://${INFISICAL_HOST}"

echo "==> Enabling ingress"
minikube addons enable ingress

echo "==> Installing Argo CD from charts/argocd"
helm dependency update "$ARGOCD_CHART" >/dev/null
helm upgrade --install argocd "$ARGOCD_CHART" \
  --namespace argocd --create-namespace \
  --values "$ARGOCD_CHART/values.yaml" \
  --wait

echo "==> Configuring Infisical for this minikube cluster"
# Argo CD deploys the chart's Secret and ingress; bootstrap only supplies local values.
# The pod annotation ensures a hostname change also restarts Infisical.
kubectl patch --local -f "$REPO_ROOT/apps/infisical/application.yaml" --type=merge \
  -p "{\"spec\":{\"source\":{\"helm\":{\"parameters\":[{\"name\":\"local.host\",\"value\":\"$INFISICAL_HOST\"},{\"name\":\"infisical-standalone.infisical.podAnnotations.local-site-url\",\"value\":\"$INFISICAL_SITE_URL\"}]}}}}" \
  -o yaml | kubectl apply -f -

echo "==> Applying root ApplicationSet"
kubectl apply -f "$REPO_ROOT/bootstrap/root-appset.yaml"

echo
echo "Argo CD is ready."
echo "  user:     admin"
echo -n "  password: "
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
echo
echo "Open the UI with:"
echo "  kubectl -n argocd port-forward svc/argocd-server 8080:80"
echo "  http://localhost:8080"

echo
echo "Infisical (after Argo CD syncs): $INFISICAL_SITE_URL"
