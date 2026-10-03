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

# shellcheck disable=SC2329,SC2317  # invoked indirectly through check()
probe() { # namespace
  local name="probe-$RANDOM"
  # Written to satisfy Pod Security "restricted" and the namespace ResourceQuota,
  # so a failure means the network policy blocked it, not admission.
  kubectl -n "$1" run "$name" --rm -i --restart=Never --quiet \
    --image=curlimages/curl:8.11.1 \
    --overrides='{"spec":{"automountServiceAccountToken":false,"securityContext":{"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"'"$name"'","image":"curlimages/curl:8.11.1","command":["curl","-fsS","--max-time","4","http://web.web-dev.svc.cluster.local/"],"resources":{"requests":{"cpu":"10m","memory":"16Mi"},"limits":{"cpu":"50m","memory":"32Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
}
# Same namespace is allowed by web-allow-same-namespace ...
check "pod in web-dev can reach web" pass probe web-dev
# ... but a pod anywhere else is stopped by the default-deny policy.
check "pod in default namespace is blocked" fail probe default
# Pod Security 'restricted' rejects a root pod. The pod has resources, so the
# quota cannot be the reason, and we assert the rejection names PodSecurity.
# shellcheck disable=SC2329,SC2317  # invoked indirectly through check()
root_pod_rejected_by_psa() {
  local out
  out=$(kubectl -n web-dev apply -f - 2>&1 <<'YAML' || true
apiVersion: v1
kind: Pod
metadata: {name: root-pod}
spec:
  containers:
    - name: root
      image: busybox:1.37
      command: [sleep, "1"]
      securityContext: {runAsUser: 0}
      resources:
        requests: {cpu: 10m, memory: 16Mi}
        limits: {cpu: 50m, memory: 32Mi}
YAML
)
  grep -q "violates PodSecurity" <<<"$out"
}
check "root pod is rejected by Pod Security admission (not by quota)" pass root_pod_rejected_by_psa
kubectl -n web-dev delete pod root-pod --ignore-not-found >/dev/null 2>&1 || true

exit $fail
