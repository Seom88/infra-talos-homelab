#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
#  destroy-tailscale-devices.sh
#  Delete Tailscale devices matching cluster hostnames via API.
#  Run BEFORE terraform destroy to prevent stale "dead" nodes.
#
#  Usage:
#    ./scripts/destroy-tailscale-devices.sh <tfvars-file> [tailnet]
#
#  Env vars required:
#    TS_OAUTH_CLIENT_ID  — Tailscale OAuth client ID
#    TS_OAUTH_SECRET     — Tailscale OAuth client secret
#
#  Example:
#    TS_OAUTH_CLIENT_ID=xxx TS_OAUTH_SECRET=yyy \
#      ./scripts/destroy-tailscale-devices.sh proxmox/environments/prod/terraform.tfvars lonk-mirfak
# ──────────────────────────────────────────────────────────────
set -euo pipefail

TFVARS="${1:?Usage: $0 <tfvars-file> [tailnet]}"
TAILNET="${2:-}"

# --- Validate env vars ---
if [[ -z "${TS_OAUTH_CLIENT_ID:-}" || -z "${TS_OAUTH_SECRET:-}" ]]; then
  echo "✗ Missing TS_OAUTH_CLIENT_ID or TS_OAUTH_SECRET"
  exit 1
fi

# --- Derive tailnet from domain if not provided ---
if [[ -z "$TAILNET" ]]; then
  # Try to read tailscale_domain from tfvars
  DOMAIN=$(grep -oE 'tailscale_domain\s*=\s*"[^"]+"' "$TFVARS" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
  if [[ -n "$DOMAIN" ]]; then
    TAILNET="${DOMAIN%.ts.net}"
  fi
fi

if [[ -z "$TAILNET" ]]; then
  echo "✗ Could not determine tailnet. Pass it as second argument."
  exit 1
fi

# --- Extract hostnames from tfvars ---
# Matches: hostname = "talos-cp1" (ignores commented lines starting with #)
HOSTNAMES=$(grep -E '^\s*hostname\s*=\s*"[^"]+"' "$TFVARS" | sed 's/.*"\([^"]*\)".*/\1/' | sort -u)

if [[ -z "$HOSTNAMES" ]]; then
  echo "⚠ No hostnames found in $TFVARS, skipping cleanup"
  exit 0
fi

echo "── Tailscale device cleanup ──"
echo "Tailnet:  $TAILNET"
echo "Hostnames: $(echo "$HOSTNAMES" | tr '\n' ' ')"

# --- Get OAuth token ---
TOKEN=$(curl -sf -X POST \
  "https://api.tailscale.com/api/v2/token" \
  -u "${TS_OAUTH_CLIENT_ID}:${TS_OAUTH_SECRET}" \
  -d "scope=device:core" | jq -r '.access_token')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "✗ Failed to get OAuth token"
  exit 1
fi

# --- List all devices ---
DEVICES=$(curl -sf \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://api.tailscale.com/api/v2/tailnet/${TAILNET}/devices")

# --- Delete matching devices ---
DELETED=0
SKIPPED=0

while IFS= read -r HOSTNAME; do
  DEVICE_ID=$(echo "$DEVICES" | jq -r --arg h "$HOSTNAME" \
    '.devices[] | select(.hostname == $h) | .id')

  if [[ -n "$DEVICE_ID" ]]; then
    if curl -sf -X DELETE \
      -H "Authorization: Bearer ${TOKEN}" \
      "https://api.tailscale.com/api/v2/tailnet/${TAILNET}/devices/${DEVICE_ID}"; then
      echo "  ✓ Deleted: $HOSTNAME ($DEVICE_ID)"
      ((DELETED++))
    else
      echo "  ✗ Failed to delete: $HOSTNAME ($DEVICE_ID)"
    fi
  else
    echo "  - Not found: $HOSTNAME"
    ((SKIPPED++))
  fi
done <<< "$HOSTNAMES"

echo ""
echo "Done: $DELETED deleted, $SKIPPED not found"
