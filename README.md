# gitops-platform

A small, complete GitOps setup you can run on a laptop: a `kind` cluster, Argo CD
reconciling everything from this repository, two environments from one set of
manifests, and guardrails that are checked in CI and then proven on a real cluster.

```
git (this repo)                       kind cluster
 ├─ apps/        ──────────────────▶  Argo CD (core)
 │   ├─ platform.yaml  (wave 0)        └─ root ──▶ platform   namespaces, default-deny, quotas
 │   └─ web.yaml       (wave 1)                  └▶ web-dev, web-staging  (ApplicationSet)
 ├─ platform/                               ▲
 ├─ workloads/web/base + overlays/{dev,staging}
 └─ clusters/kind/root.yaml.tmpl   the only thing applied by hand
```

## Run it

Needs Docker, [`kind`](https://kind.sigs.k8s.io), `kubectl`, and `envsubst`. Argo CD clones from the remote, so the commit you
deploy must be pushed.

```bash
make up       # cluster + Argo CD + root app, waits until every app is Synced/Healthy
make verify   # proves replicas, network policy, and pod security on the live cluster
make down
make check    # no cluster needed: schema validation + policy checks
```

## How it is put together

**App of apps.** One hand-applied `root` Application points at `apps/`. Everything
below it is declared in git, so there is no `kubectl apply` to forget.

**Ordering without scripts.** `platform` (namespaces, policies) is sync wave 0 and
the workloads are wave 1. The workloads also retry with backoff, because
Argo CD's wave ordering does not wait for a different Application's health.

**One set of manifests, two environments.** `workloads/web/base` plus a Kustomize
overlay per environment. `staging` differs from `dev` by one patch (replicas). An
`ApplicationSet` generates `web-dev` and `web-staging` from a list; adding an
environment is one line and one overlay directory.

**Testable from any branch.** In git the child apps track `HEAD`. `scripts/up.sh`
renders the root app with the repo URL and revision you choose, and the root app
patches its children to match, so a pull request is tested as itself instead of
as the default branch.

## Guardrails, and where each is enforced

| Guardrail | Static check (`make check`, every PR) | Proven on the cluster (`make verify`) |
|---|---|---|
| Containers set cpu/memory requests and limits | `scripts/check-policy.py` | |
| No `:latest` / unpinned images | `scripts/check-policy.py` | |
| Non-root, no privilege escalation | `scripts/check-policy.py` | Pod Security `restricted` rejects a root pod |
| Default-deny network policy per namespace | `scripts/check-policy.py` | A pod outside the namespace cannot reach `web`; one inside can |
| Manifests match their schemas (including Argo CD CRDs) | `kubeconform -strict` | |
| Overlays render what they claim | | staging has 2 replicas, dev has 1 |

The static checker was tested by deliberately breaking the manifests and watching
it fail, which is the only way to know a check works.

## What running it taught (all fixed, all in the history)

These only showed up on a live cluster, which is why `make verify` exists:

- **`core-install` has no `default` AppProject.** The project is created by
  `argocd-server` at startup and core mode has no server, so every Application was
  rejected until `clusters/kind/project-default.yaml` was applied.
- **Default-deny egress also blocks your own test pod.** The first "can reach web"
  check failed for the right reason (no DNS, no egress). Each namespace now gets
  exactly DNS plus same-namespace egress back.
- **A ResourceQuota rejects pods that omit requests/limits.** That includes the
  test probes, so they declare resources, and the Pod Security check asserts the
  rejection message says `violates PodSecurity`, so a quota failure cannot pass
  for a pass.
- **"Synced/Healthy" can be stale.** `wait-synced.sh` checks the synced revision
  equals the one just pushed; without that an old healthy sync looks like a
  finished new one.

## Deliberately out of scope

- Secrets. A real setup adds Sealed Secrets, SOPS, or an external secrets operator.
- Argo CD with SSO/RBAC and the UI (`core-install` is used on purpose: no dex, no API server).
- Ingress, TLS, and observability for the workloads.
- Multiple clusters. The `destination` is the local cluster; a fleet would use
  cluster generators in the `ApplicationSet`.

## License

MIT
