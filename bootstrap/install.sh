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

  echo "==> Enable ingress"
  minikube addon enable ingress
fi
kubectl config use-context minikube >/dev/null

echo "==> Installing Argo CD from charts/argocd"
helm dependency update "$ARGOCD_CHART" >/dev/null
helm upgrade --install argocd "$ARGOCD_CHART" \
  --namespace argocd --create-namespace \
  --values "$ARGOCD_CHART/values.yaml" \
  --wait

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
