# ──────────────────────────────────────────────
#  infra-homelab — Talos + Proxmox helper tasks
# ──────────────────────────────────────────────
# Uses Tailscale IPs for management when the cluster is reachable,
# falls back to LAN IPs from terraform.tfvars otherwise.

talosconfig := "./secrets/talosconfig.yaml"
kubeconfig  := "./secrets/kubeconfig.yaml"

# LAN IPs from terraform.tfvars (fallback when cluster is unreachable)
lan_first := `grep -A2 'hostname = "talos-cp1"' terraform.tfvars | awk -F'"' '/ip/{print $2}'`
lan_nodes := `awk -F'"' '/ip/{printf "%s%s", sep, $2; sep=","}' terraform.tfvars`

# Helper — get Tailscale IP for the first node (fallback to LAN)
ts_first := `talosctl --talosconfig ./secrets/talosconfig.yaml get members -o json -n {{lan_first}} 2>/dev/null | jq -rs '.[0].spec.addresses[0]' 2>/dev/null || echo "{{lan_first}}"`

# Generate talosconfig and kubeconfig from terraform state (only if missing)
gen-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p ./secrets
    if [[ ! -f "{{talosconfig}}" || ! -f "{{kubeconfig}}" ]]; then
        echo "→ Regenerating secrets from terraform state..."
        terraform output -raw talosconfig > "{{talosconfig}}"
        terraform output -raw kubeconfig  > "{{kubeconfig}}"
        echo "✓ done"
    else
        echo "✓ secrets already exist"
    fi

# Merge secrets into local talosctl and kubectl config
setup-cli:
    #!/usr/bin/env bash
    set -euo pipefail
    just gen-secrets
    # talosctl
    mkdir -p ~/.talos
    if [[ -f ~/.talos/config ]]; then
        talosctl config merge "{{talosconfig}}"
    else
        cp "{{talosconfig}}" ~/.talos/config
    fi
    echo "✓ talosctl configured"
    # kubectl
    mkdir -p ~/.kube
    KUBECONFIG=~/.kube/config:"{{kubeconfig}}" \
      kubectl config view --flatten > /tmp/kube-merge
    mv /tmp/kube-merge ~/.kube/config
    echo "✓ kubectl configured"

# Show cluster info: Talos version, extensions, schematic ID, nodes
status:
    #!/usr/bin/env bash
    set -euo pipefail
    FIRST=$(talosctl --talosconfig {{talosconfig}} get members -o json -n {{lan_first}} 2>/dev/null \
      | jq -rs '.[0].spec.addresses[0]' 2>/dev/null || echo "{{lan_first}}")
    echo "── Version ──"
    talosctl --talosconfig {{talosconfig}} version --short -n "$FIRST"
    echo ""
    echo "── Extensions ──"
    talosctl --talosconfig {{talosconfig}} get extensions -n "$FIRST"
    echo ""
    echo "── Nodes ──"
    talosctl --talosconfig {{talosconfig}} get members -n "$FIRST"

# Check current version and schematic ID for planning an upgrade
get-schematic-id:
    #!/usr/bin/env bash
    set -euo pipefail
    FIRST=$(talosctl --talosconfig {{talosconfig}} get members -o json -n {{lan_first}} 2>/dev/null \
      | jq -rs '.[0].spec.addresses[0]' 2>/dev/null || echo "{{lan_first}}")
    echo "Schematic ID:"
    talosctl --talosconfig {{talosconfig}} get extensions -n "$FIRST" \
      -o json | jq -r 'select(.spec.metadata.name=="schematic") | .spec.metadata.version'
