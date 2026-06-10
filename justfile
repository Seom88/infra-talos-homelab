# ──────────────────────────────────────────────
#  infra-homelab — Talos + Proxmox helper tasks
# ──────────────────────────────────────────────
#  All commands run from the repo root.
#  Terraform state lives in proxmox/.
#  Generated secrets go to ./secrets/ (.gitignored).

tf_root    := "./proxmox"
secrets    := "./secrets"
talosconfig := secrets + "/talosconfig.yaml"
kubeconfig  := secrets + "/kubeconfig.yaml"

# LAN IPs from terraform.tfvars (fallback when cluster is unreachable)
lan_first := `grep -A2 'hostname = "talos-cp1"' ./proxmox/terraform.tfvars | awk -F'"' '/ip/{print $2}'`
lan_nodes := `awk -F'"' '/ip/{printf "%s%s", sep, $2; sep=","}' ./proxmox/terraform.tfvars`

# Generate talosconfig + kubeconfig from terraform state
gen-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p {{secrets}}
    cd {{tf_root}}
    terraform output -raw talosconfig > {{talosconfig}}
    terraform output -raw kubeconfig  > {{kubeconfig}}
    echo "✓ secrets regenerated"

# Merge secrets into local talosctl and kubectl config
setup-cli:
    #!/usr/bin/env bash
    set -euo pipefail
    just gen-secrets
    # talosctl
    mkdir -p ~/.talos
    if [[ -f ~/.talos/config ]]; then
        talosctl config merge {{talosconfig}}
    else
        cp {{talosconfig}} ~/.talos/config
    fi
    echo "✓ talosctl configured"
    # kubectl
    mkdir -p ~/.kube
    KUBECONFIG=~/.kube/config:{{kubeconfig}} \
      kubectl config view --flatten > /tmp/kube-merge
    mv /tmp/kube-merge ~/.kube/config
    echo "✓ kubectl configured"

# Show cluster info: Talos version, extensions, schematic, nodes
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

# Compute schematic ID from schematic.yaml via Talos Image Factory API
get-schematic-id:
    curl -sf -X POST --data-binary @schematic.yaml https://factory.talos.dev/schematics | jq -r '.id'

# Read schematic ID from the running cluster (for upgrade planning)
cluster-schematic-id:
    #!/usr/bin/env bash
    set -euo pipefail
    FIRST=$(talosctl --talosconfig {{talosconfig}} get members -o json -n {{lan_first}} 2>/dev/null \
      | jq -rs '.[0].spec.addresses[0]' 2>/dev/null || echo "{{lan_first}}")
    echo "Schematic ID (cluster):"
    talosctl --talosconfig {{talosconfig}} get extensions -n "$FIRST" \
      -o json | jq -r 'select(.spec.metadata.name=="schematic") | .spec.metadata.version'
