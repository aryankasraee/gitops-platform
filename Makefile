SCHEMAS = -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

.PHONY: check up verify down
check:
	@for d in platform apps workloads/web/overlays/dev workloads/web/overlays/staging; do \
	  echo "== $$d"; kubectl kustomize $$d | kubeconform -strict -summary $(SCHEMAS) || exit 1; done
	python3 scripts/check-policy.py
up:
	scripts/up.sh
verify:
	scripts/verify-cluster.sh
down:
	scripts/down.sh
