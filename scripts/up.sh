#!/usr/bin/env bash
# Create a kind cluster, install Argo CD (core), hand it the root app, wait.
#   REPO_URL   git repo Argo CD should read (default: this checkout's origin)
#   REVISION   branch, tag or commit to deploy (default: current commit; it must be pushed)
set -euo pipefail
cd "$(dirname "$0")/.."

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.5.3}"
REPO_URL="${REPO_URL:-$(git remote get-url origin | sed -E 's#^git@github.com:#https://github.com/#')}"
REVISION="${REVISION:-$(git rev-parse HEAD)}"

if ! git ls-remote --exit-code "$REPO_URL" "$REVISION" >/dev/null 2>&1 \
   && ! git ls-remote "$REPO_URL" | grep -q "^$REVISION"; then
  echo "revision $REVISION is not on $REPO_URL: push it first (Argo CD clones from the remote)" >&2
  exit 1
fi

kind get clusters | grep -qx gitops-platform || kind create cluster --config clusters/kind/kind.yaml --wait 120s

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# Server-side apply: the Argo CD CRDs are too large for client-side annotations.
kubectl apply --server-side --force-conflicts -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/core-install.yaml" >/dev/null

echo "waiting for Argo CD"
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

kubectl apply -f clusters/kind/project-default.yaml >/dev/null
REPO_URL="$REPO_URL" REVISION="$REVISION" envsubst < clusters/kind/root.yaml.tmpl | kubectl apply -f - >/dev/null
echo "root app applied for $REPO_URL @ $REVISION"

REVISION="$REVISION" scripts/wait-synced.sh
