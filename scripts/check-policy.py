#!/usr/bin/env python3
"""Static policy checks on the rendered manifests. No cluster needed.

Rules (each one is a real incident class, not decoration):
  * every container sets cpu/memory requests and limits
  * no ':latest' or untagged images
  * pods run as non-root with privilege escalation off
  * every environment namespace has a default-deny NetworkPolicy
"""
import subprocess, sys
import yaml

KUSTOMIZATIONS = ["platform", "workloads/web/overlays/dev", "workloads/web/overlays/staging"]
errors = []
namespaces, denied = set(), set()

for path in KUSTOMIZATIONS:
    out = subprocess.run(["kubectl", "kustomize", path], capture_output=True, text=True, check=True).stdout
    for doc in filter(None, yaml.safe_load_all(out)):
        kind, name = doc["kind"], doc["metadata"]["name"]
        if kind == "Namespace":
            namespaces.add(name)
        if kind == "NetworkPolicy" and doc["spec"].get("podSelector") == {} \
           and set(doc["spec"].get("policyTypes", [])) >= {"Ingress", "Egress"} and not doc["spec"].get("ingress"):
            denied.add(doc["metadata"]["namespace"])
        if kind in ("Deployment", "StatefulSet", "DaemonSet"):
            pod = doc["spec"]["template"]["spec"]
            psc = pod.get("securityContext", {})
            for c in pod["containers"]:
                who = f"{kind}/{name} container {c['name']}"
                img = c["image"]
                if ":" not in img.split("/")[-1] or img.endswith(":latest"):
                    errors.append(f"{who}: image '{img}' must be pinned to a tag")
                res = c.get("resources", {})
                for section in ("requests", "limits"):
                    for r in ("cpu", "memory"):
                        if r not in res.get(section, {}):
                            errors.append(f"{who}: missing resources.{section}.{r}")
                sc = c.get("securityContext", {})
                if not (psc.get("runAsNonRoot") or sc.get("runAsNonRoot")):
                    errors.append(f"{who}: runAsNonRoot is not set")
                if sc.get("allowPrivilegeEscalation") is not False:
                    errors.append(f"{who}: allowPrivilegeEscalation must be false")

for ns in sorted(namespaces - denied):
    errors.append(f"namespace {ns}: no default-deny NetworkPolicy")

if errors:
    print("policy check FAILED"); [print(" -", e) for e in sorted(set(errors))]; sys.exit(1)
print(f"policy check passed ({len(namespaces)} namespaces, all with default-deny)")
