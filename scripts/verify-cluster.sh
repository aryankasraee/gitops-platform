#!/usr/bin/env bash
# Prove the cluster behaves the way the manifests claim.
set -euo pipefail

fail=0
check() { # description, expected (pass|fail), command...
  local desc=$1 want=$2; shift 2
  if "$@" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then echo "ok   $desc"; else echo "FAIL $desc (wanted $want, got $got)"; fail=1; fi
}

kubectl -n web-staging rollout status deploy/web --timeout=120s >/dev/null
check "staging runs 2 replicas (overlay patch applied)" pass \
  test "$(kubectl -n web-staging get deploy web -o jsonpath='{.spec.replicas}')" = 2
check "dev runs 1 replica" pass \
  test "$(kubectl -n web-dev get deploy web -o jsonpath='{.spec.replicas}')" = 1

probe() { # namespace
  local name="probe-$RANDOM"
  # Written to satisfy Pod Security "restricted", so a failure means the network
  # policy blocked it, not the admission controller.
  kubectl -n "$1" run "$name" --rm -i --restart=Never --quiet \
    --image=curlimages/curl:8.11.1 \
    --overrides='{"spec":{"automountServiceAccountToken":false,"securityContext":{"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"'"$name"'","image":"curlimages/curl:8.11.1","command":["curl","-fsS","--max-time","4","http://web.web-dev.svc.cluster.local/"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
}
# Same namespace is allowed by web-allow-same-namespace ...
check "pod in web-dev can reach web" pass probe web-dev
# ... but a pod anywhere else is stopped by the default-deny policy.
check "pod in default namespace is blocked" fail probe default
# Pod Security 'restricted' rejects a root pod in an environment namespace.
check "root pod is rejected by Pod Security admission" fail \
  kubectl -n web-dev run root-pod --image=busybox:1.37 --restart=Never --command -- sleep 1

exit $fail
