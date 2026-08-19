#!/usr/bin/env bash
set -euo pipefail

command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required to remove control-plane taints (allow_scheduling). Install it and re-apply."; exit 1; }
KUBECONFIG_FILE="$(mktemp)"
trap 'rm -f "$KUBECONFIG_FILE"' EXIT
printf '%s' "${KUBECONFIG_CONTENT}" > "$KUBECONFIG_FILE"

for host in "$@"; do
  ok=false
  for i in $(seq 1 60); do
    if kubectl --kubeconfig "$KUBECONFIG_FILE" get node "$host" >/dev/null 2>&1; then
      taints="$(kubectl --kubeconfig "$KUBECONFIG_FILE" get node "$host" -o jsonpath='{.spec.taints[*].key}' 2>/dev/null || true)"
      if ! printf '%s' "$taints" | grep -q "node-role.kubernetes.io/control-plane"; then
        ok=true
        break
      fi
      if kubectl --kubeconfig "$KUBECONFIG_FILE" taint nodes "$host" node-role.kubernetes.io/control-plane- >/dev/null 2>&1; then
        ok=true
        break
      fi
    fi
    sleep 5
  done
  if [ "$ok" != "true" ]; then
    echo "could not remove control-plane taint from node '$host' within 5 minutes" >&2
    exit 1
  fi
  echo "removed control-plane taint from '$host'"
done
