# Runbook: an Argo CD Application is OutOfSync or Degraded

```bash
kubectl -n argocd get applications
kubectl -n argocd describe application <name> | sed -n '/Status:/,$p'
```

## OutOfSync and it will not heal

1. **Is `selfHeal` fighting something else?** Another controller (HPA, an operator)
   may be editing a field Argo CD owns. Look at the diff: the argocd CLI or the
   `status.resources` section of the Application shows which field.
2. **Is the revision what you think?** `kubectl -n argocd get application <name> -o jsonpath='{.spec.source.targetRevision}'`.
   Children track `HEAD` in git; the root app overrides it per environment.
3. **Is the repo reachable?** `kubectl -n argocd logs deploy/argocd-repo-server --tail=50`.

## Degraded

1. `kubectl -n <env-namespace> get pods` and `describe` the failing pod.
2. `FailedCreate` with a Pod Security message: the workload broke the `restricted`
   profile. Fix the manifest; do not weaken the namespace label.
3. `exceeded quota`: raise it in `platform/quota.yaml` through a pull request.

## Never

Never "fix" a sync problem with `kubectl edit` on a managed object. `selfHeal`
reverts it within minutes and you have taught nobody anything. Change git.
