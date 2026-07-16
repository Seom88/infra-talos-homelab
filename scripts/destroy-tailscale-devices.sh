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
echo "Requesting OAuth token..."
TOKEN_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "https://api.tailscale.com/api/v2/oauth/token" \
  -d "client_id=${TS_OAUTH_CLIENT_ID}" \
  -d "client_secret=${TS_OAUTH_SECRET}")
HTTP_CODE=$(echo "$TOKEN_RESPONSE" | tail -1)
TOKEN_BODY=$(echo "$TOKEN_RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "✗ OAuth token request failed (HTTP $HTTP_CODE)"
  echo "  Response: $TOKEN_BODY"
  exit 1
fi

TOKEN=$(echo "$TOKEN_BODY" | jq -r '.access_token')
if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "✗ Failed to extract access_token from response"
  echo "  Response: $TOKEN_BODY"
  exit 1
fi
echo "✓ OAuth token obtained"

# --- List all devices ---
echo "Fetching devices from Tailscale..."
DEVICES_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://api.tailscale.com/api/v2/tailnet/-/devices")
HTTP_CODE=$(echo "$DEVICES_RESPONSE" | tail -1)
DEVICES_BODY=$(echo "$DEVICES_RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "✗ Failed to list devices (HTTP $HTTP_CODE)"
  echo "  Response: $DEVICES_BODY"
  exit 1
fi

DEVICE_COUNT=$(echo "$DEVICES_BODY" | jq '.devices | length')
echo "✓ Found $DEVICE_COUNT devices in tailnet"

# --- Delete matching devices ---
DELETED=0
SKIPPED=0

while IFS= read -r HOSTNAME; do
  DEVICE_ID=$(echo "$DEVICES_BODY" | jq -r --arg h "$HOSTNAME" \
    '.devices[] | select(.hostname == $h) | .id')

  if [[ -n "$DEVICE_ID" ]]; then
    echo "  Deleting $HOSTNAME ($DEVICE_ID)..."
    DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE \
      -H "Authorization: Bearer ${TOKEN}" \
      "https://api.tailscale.com/api/v2/device/${DEVICE_ID}")
    DELETE_CODE=$(echo "$DELETE_RESPONSE" | tail -1)
    if [[ "$DELETE_CODE" == "200" ]]; then
      echo "  ✓ Deleted: $HOSTNAME"
      DELETED=$((DELETED + 1))
    else
      DELETE_BODY=$(echo "$DELETE_RESPONSE" | sed '$d')
      echo "  ✗ Failed to delete $HOSTNAME (HTTP $DELETE_CODE): $DELETE_BODY"
    fi
  else
    echo "  - Not found in Tailscale: $HOSTNAME"
    SKIPPED=$((SKIPPED + 1))
  fi
done <<< "$HOSTNAMES"

echo ""
echo "Done: $DELETED deleted, $SKIPPED not found"
