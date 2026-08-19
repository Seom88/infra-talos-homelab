#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  talos-upgrade.sh
#  Rolling upgrade of Talos nodes to the latest stable release.
#
#  talos_version is a bootstrap-only pin: bumping it in terraform
#  recreates the VMs (etcd wipe, control-plane VIP downtime). Real
#  upgrades run IN PLACE, node by node, via `talosctl upgrade`.
#
#  Usage:
#    ./scripts/talos-upgrade.sh --root proxmox --env prod
#    ./scripts/talos-upgrade.sh --root libvirt
#
#  Secrets (talosconfig) required:
#    proxmox: ./secrets/<env>/talosconfig.yaml   (just setup-cli)
#    libvirt: ./secrets/libvirt/talosconfig.yaml (just setup-libvirt-cli)
#
#  Steps:
#    1. Resolve the latest stable Talos release from the GitHub API
#    2. Compute the schematic ID for the custom extensions
#    3. Upgrade each node in place (control planes first, then workers)
#    4. Pin-sync the new version into both variables.tf files
# ──────────────────────────────────────────────────────────────
set -euo pipefail

# Always operate from the repo root, regardless of the caller's cwd.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

print_usage() {
  echo "Usage: $0 --root {proxmox|libvirt} [--env <env>]"
  echo "  --root  Infrastructure provider (required)"
  echo "  --env   Environment for --root proxmox (default: prod)"
}

# --- Parse arguments ---
ROOT=""
ENV="prod"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="${2:-}"
      if [[ -z "$ROOT" ]]; then
        echo "✗ --root requires a value (proxmox|libvirt)"
        print_usage
        exit 1
      fi
      shift 2
      ;;
    --env)
      ENV="${2:-}"
      if [[ -z "$ENV" ]]; then
        echo "✗ --env requires a value"
        print_usage
        exit 1
      fi
      shift 2
      ;;
    *)
      echo "✗ Unknown argument: $1"
      print_usage
      exit 1
      ;;
  esac
done

case "$ROOT" in
  proxmox|libvirt) ;;
  *)
    echo "✗ --root is required and must be 'proxmox' or 'libvirt' (got: '${ROOT:-}')"
    print_usage
    exit 1
    ;;
esac

# --- Resolve paths per root ---
if [[ "$ROOT" == "proxmox" ]]; then
  TALOSCONFIG="./secrets/${ENV}/talosconfig.yaml"
  TFVARS="proxmox/environments/${ENV}/terraform.tfvars"
  SCHEMATIC_FILE="schematic-${ENV}.yaml"
  IMAGE_KIND="installer-secureboot"
  CLI_HINT="just setup-cli"
else
  TALOSCONFIG="./secrets/libvirt/talosconfig.yaml"
  TFVARS="libvirt/terraform.tfvars"
  SCHEMATIC_FILE="schematic-dev.yaml"
  IMAGE_KIND="nocloud-installer"
  CLI_HINT="just setup-libvirt-cli"
fi

if [[ ! -f "$TALOSCONFIG" ]]; then
  echo "✗ talosconfig not found: $TALOSCONFIG"
  echo "  Generate it first with: ${CLI_HINT}"
  exit 1
fi

if [[ ! -f "$TFVARS" ]]; then
  echo "✗ Terraform vars file not found: $TFVARS"
  exit 1
fi

# --- Extract node IPs from a tfvars block (nodes_cp | nodes_worker) ---
# Two passes over the file: enter on the opening "block = [" line, collect
# every non-commented `ip = "..."` line, leave on the closing "]". Each pass
# scans the whole file independently, so the result is never affected by the
# lexical order of the blocks. Commented-out nodes (e.g. the disabled workers
# in proxmox/prod) are ignored.
extract_ips() {
  local block="$1"
  local file="$2"
  awk -v block="$block" '
    !/^[[:space:]]*#/ && $0 ~ "^[[:space:]]*" block "[[:space:]]*=[[:space:]]*\\[" { in_block = 1; next }
    in_block && /^[[:space:]]*]/ { in_block = 0; next }
    in_block && !/^[[:space:]]*#/ && /^[[:space:]]*ip[[:space:]]*=/ { print }
  ' "$file" | sed -E 's/.*=\s*"([^"]+)".*/\1/'
}

echo "── Talos upgrade ───────────────────────────────"
echo "Root:   $ROOT"
echo "Env:    $ENV"
echo "Talosconfig: $TALOSCONFIG"

# --- 1. Resolve the latest stable Talos release ---
echo ""
echo "── Resolving latest stable version ──"
LATEST=$(curl -sf https://api.github.com/repos/siderolabs/talos/releases/latest | jq -r '.tag_name' | sed 's/^v//') || {
  echo "✗ Failed to resolve the latest stable Talos version from the GitHub API"
  echo "  Check network access to api.github.com"
  exit 1
}
if [[ ! "$LATEST" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "✗ Unexpected version returned by the GitHub API: '$LATEST'"
  exit 1
fi
echo "✓ Latest stable: v${LATEST}"

# --- 2. Compute the schematic ID (custom extensions image) ---
echo ""
echo "── Schematic ──"
if [[ ! -f "$SCHEMATIC_FILE" ]]; then
  echo "✗ Schematic file not found: $SCHEMATIC_FILE"
  exit 1
fi
SCHEMATIC_ID=$(curl -sf -X POST --data-binary @"$SCHEMATIC_FILE" https://factory.talos.dev/schematics | jq -r '.id') || {
  echo "✗ Failed to compute the schematic ID from the Talos Image Factory"
  echo "  Check ${SCHEMATIC_FILE} and network access to factory.talos.dev"
  exit 1
}
if [[ -z "$SCHEMATIC_ID" || "$SCHEMATIC_ID" == "null" ]]; then
  echo "✗ Invalid schematic ID returned by the Image Factory"
  exit 1
fi
echo "✓ Schematic ID: $SCHEMATIC_ID"

# --- 3. Extract node IPs (control planes first, then workers) ---
echo ""
echo "── Nodes ──"
mapfile -t CP_IPS < <(extract_ips nodes_cp "$TFVARS")
mapfile -t WORKER_IPS < <(extract_ips nodes_worker "$TFVARS")

if [[ ${#CP_IPS[@]} -eq 0 ]]; then
  echo "✗ No control-plane node IPs found in $TFVARS (expected a 'nodes_cp = [...]' block)"
  exit 1
fi
if [[ ${#WORKER_IPS[@]} -eq 0 ]]; then
  echo "⚠ No worker node IPs found in $TFVARS (workers commented out?)"
  echo "  Continuing with control-plane nodes only"
fi
echo "Control plane: ${CP_IPS[*]}"
if [[ ${#WORKER_IPS[@]} -gt 0 ]]; then
  echo "Workers:       ${WORKER_IPS[*]}"
fi

# --- 4. Check the running Talos version on the first control-plane node ---
FIRST_IP="${CP_IPS[0]}"
echo ""
echo "── Version check (${FIRST_IP}) ──"
VERSION_OUTPUT=$(talosctl --talosconfig "$TALOSCONFIG" version --short -n "$FIRST_IP" 2>&1) || {
  echo "✗ Failed to query the Talos version on ${FIRST_IP}"
  echo "  Is the cluster up and reachable from this machine?"
  exit 1
}

# `talosctl version --short` prints the CLIENT (talosctl binary) version
# first, then the Server section with the node's Talos version. The client
# and server versions can differ, so only trust the Server section.
SERVER_LINE=$(printf '%s\n' "$VERSION_OUTPUT" | awk '/^[[:space:]]*Server:/{in_server=1; next} in_server && /v[0-9]+\.[0-9]+\.[0-9]+/{print; exit}')
if [[ -z "$SERVER_LINE" ]]; then
  echo "✗ Could not parse the server version from talosctl output:"
  printf '%s\n' "$VERSION_OUTPUT"
  exit 1
fi

CLIENT_VERSION=$(printf '%s\n' "$VERSION_OUTPUT" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
RUNNING=$(printf '%s\n' "$SERVER_LINE" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)

echo "talosctl client: ${CLIENT_VERSION:-unknown}"
echo "Server (${FIRST_IP}): $RUNNING"
echo "Target:            v${LATEST}"

# --- 5. Rolling upgrade: control planes first, then workers ---
if [[ "$RUNNING" == "v${LATEST}" ]]; then
  echo ""
  echo "✓ ${FIRST_IP} is already at v${LATEST} — nodes are up to date"
  echo "  Skipping the rolling upgrade"
else
  IMAGE="factory.talos.dev/${IMAGE_KIND}/${SCHEMATIC_ID}:v${LATEST}"
  ALL_IPS=("${CP_IPS[@]}" "${WORKER_IPS[@]}")
  echo ""
  echo "── Rolling upgrade ──"
  echo "Image: ${IMAGE}"
  echo "Nodes: ${ALL_IPS[*]}"

  for IP in "${ALL_IPS[@]}"; do
    echo ""
    echo "── Upgrading ${IP} ──"
    talosctl --talosconfig "$TALOSCONFIG" upgrade -n "$IP" --image "$IMAGE" --wait
    echo "✓ ${IP} upgraded to v${LATEST}"
    echo "── Health check: ${IP} ──"
    talosctl --talosconfig "$TALOSCONFIG" health --server=false --wait-timeout 10m -n "$IP"
    echo "✓ ${IP} healthy"
  done
  echo ""
  echo "✓ Rolling upgrade complete"
fi

# --- 6. Pin-sync the version into both variables.tf (always) ---
# Only touch `default` lines inside variable "talos_version" { ... } blocks.
echo ""
echo "── Pin sync ──"
sed -i -E '/^variable "talos_version" \{/,/^\}/ s/^([[:space:]]*default[[:space:]]*=[[:space:]]*")[0-9]+\.[0-9]+\.[0-9]+(")/\1'"$LATEST"'\2/' \
  proxmox/variables.tf libvirt/variables.tf
echo "✓ pins synced (talos_version = $LATEST in proxmox/variables.tf and libvirt/variables.tf)"