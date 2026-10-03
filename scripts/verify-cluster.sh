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
  kubectl -n "$1" run "probe-$RANDOM" --rm -i --restart=Never --quiet \
    --image=curlimages/curl:8.11.1 --overrides='{"spec":{"automountServiceAccountToken":false}}' \
    --command -- curl -fsS --max-time 4 "http://web.web-dev.svc.cluster.local/"
}
# Same namespace is allowed by web-allow-same-namespace ...
check "pod in web-dev can reach web" pass probe web-dev
# ... but a pod anywhere else is stopped by the default-deny policy.
check "pod in default namespace is blocked" fail probe default
# Pod Security 'restricted' rejects a root pod in an environment namespace.
check "root pod is rejected by Pod Security admission" fail \
  kubectl -n web-dev run root-pod --image=busybox:1.37 --restart=Never --command -- sleep 1

exit $fail
