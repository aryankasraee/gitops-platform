#!/usr/bin/env bash
# Wait until every Argo CD Application is Synced and Healthy.
set -euo pipefail
timeout=${1:-420}
want="root platform web-dev web-staging"
start=$SECONDS
while (( SECONDS - start < timeout )); do
  ok=1
  for app in $want; do
    st=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
    [[ "$st" == "Synced/Healthy" ]] || ok=0
  done
  if (( ok )); then echo "all applications Synced/Healthy after $((SECONDS-start))s"; exit 0; fi
  sleep 5
done
echo "timed out; current state:" >&2
kubectl -n argocd get applications >&2 || true
kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name}: {.status.conditions[*].message}{"\n"}{end}' >&2 || true
exit 1
