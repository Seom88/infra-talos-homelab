# ──────────────────────────────────────────────
#  infra-homelab — Talos + Proxmox helper tasks
# ──────────────────────────────────────────────
#  All commands run from the repo root.
#  Terraform:  proxmox/environments/<env>/
#  Secrets:    ./secrets/<env>/          (.gitignored)
#  Usage:      just tf_env=dev <task>    (default: prod)
#
#  plan/apply/gen-secrets auto-init before running,
#  so you can switch environments freely:
#    just tf_env=dev tf-apply   # work on dev
#    just tf_apply              # work on prod (no cross-talk)

tf_root := "./proxmox"
tf_env := "prod"

# ── Terraform ──────────────────────────────────

# Init terraform with local backend for an environment
tf-init:
    terraform -chdir={{ tf_root }} init -reconfigure \
      -backend-config="path=environments/{{ tf_env }}/terraform.tfstate"

# Plan changes (auto-inits to ensure correct backend)
tf-plan:
    terraform -chdir={{ tf_root }} init -reconfigure \
      -backend-config="path=environments/{{ tf_env }}/terraform.tfstate"
    terraform -chdir={{ tf_root }} plan \
      -var-file=environments/{{ tf_env }}/terraform.tfvars

# Apply changes (auto-inits to ensure correct backend)
tf-apply:
    terraform -chdir={{ tf_root }} init -reconfigure \
      -backend-config="path=environments/{{ tf_env }}/terraform.tfstate"
    terraform -chdir={{ tf_root }} apply \
      -var-file=environments/{{ tf_env }}/terraform.tfvars

# Destroy an environment (auto-inits to ensure correct backend)
tf-destroy:
    terraform -chdir={{ tf_root }} init -reconfigure \
      -backend-config="path=environments/{{ tf_env }}/terraform.tfstate"
    terraform -chdir={{ tf_root }} destroy \
      -var-file=environments/{{ tf_env }}/terraform.tfvars

# ── Secrets ────────────────────────────────────

# Generate talosconfig + kubeconfig from terraform state
gen-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$PWD"
    SECRETS="$ROOT/secrets/{{ tf_env }}"
    mkdir -p "$SECRETS"
    terraform -chdir={{ tf_root }} init -reconfigure \
      -backend-config="path=environments/{{ tf_env }}/terraform.tfstate"
    terraform -chdir={{ tf_root }} output -raw talosconfig > "$SECRETS/talosconfig.yaml"
    terraform -chdir={{ tf_root }} output -raw kubeconfig  > "$SECRETS/kubeconfig.yaml"
    echo "✓ secrets regenerated ({{ tf_env }})"

# Merge secrets into local talosctl and kubectl config
setup-cli:
    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$PWD"
    just tf_env="{{ tf_env }}" gen-secrets
    SECRETS="$ROOT/secrets/{{ tf_env }}"
    TC="$SECRETS/talosconfig.yaml"
    KC="$SECRETS/kubeconfig.yaml"
    # talosctl
    mkdir -p ~/.talos
    if [[ -f ~/.talos/config ]]; then
        talosctl config merge "$TC"
    else
        cp "$TC" ~/.talos/config
    fi
    echo "✓ talosctl configured ({{ tf_env }})"
    # kubectl
    mkdir -p ~/.kube
    KUBECONFIG="$KC":~/.kube/config \
      kubectl config view --flatten > /tmp/kube-merge
    mv /tmp/kube-merge ~/.kube/config
    echo "✓ kubectl configured ({{ tf_env }})"

# ── Libvirt ───────────────────────────────────

libvirt_root := "./libvirt"

# Init libvirt terraform
tf-libvirt-init:
    terraform -chdir={{ libvirt_root }} init -reconfigure

# Plan libvirt changes
tf-libvirt-plan:
    terraform -chdir={{ libvirt_root }} init -reconfigure
    terraform -chdir={{ libvirt_root }} plan

# Apply libvirt changes
tf-libvirt-apply:
    terraform -chdir={{ libvirt_root }} init -reconfigure
    terraform -chdir={{ libvirt_root }} apply

# Destroy libvirt environment
tf-libvirt-destroy:
    terraform -chdir={{ libvirt_root }} init -reconfigure
    terraform -chdir={{ libvirt_root }} destroy

# Generate secrets from libvirt terraform state
gen-libvirt-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$PWD"
    SECRETS="$ROOT/secrets/libvirt"
    mkdir -p "$SECRETS"
    terraform -chdir={{ libvirt_root }} init -reconfigure
    terraform -chdir={{ libvirt_root }} output -raw talosconfig > "$SECRETS/talosconfig.yaml"
    terraform -chdir={{ libvirt_root }} output -raw kubeconfig  > "$SECRETS/kubeconfig.yaml"
    echo "✓ secrets regenerated (libvirt)"

# Setup CLI for libvirt cluster
setup-libvirt-cli:
    #!/usr/bin/env bash
    set -euo pipefail
    ROOT="$PWD"
    just gen-libvirt-secrets
    SECRETS="$ROOT/secrets/libvirt"
    TC="$SECRETS/talosconfig.yaml"
    KC="$SECRETS/kubeconfig.yaml"
    # talosctl
    mkdir -p ~/.talos
    if [[ -f ~/.talos/config ]]; then
        talosctl config merge "$TC"
    else
        cp "$TC" ~/.talos/config
    fi
    echo "✓ talosctl configured (libvirt)"
    # kubectl
    mkdir -p ~/.kube
    KUBECONFIG="$KC":~/.kube/config \
      kubectl config view --flatten > /tmp/kube-merge
    mv /tmp/kube-merge ~/.kube/config
    echo "✓ kubectl configured (libvirt)"

# ── Cluster Status ─────────────────────────────

# Show Talos version, extensions, and nodes
status:
    #!/usr/bin/env bash
    set -euo pipefail
    TC="./secrets/{{ tf_env }}/talosconfig.yaml"
    ENV_DIR="{{ tf_root }}/environments/{{ tf_env }}"
    FIRST=$(awk -F'"' '/ip/{print $2; exit}' "$ENV_DIR/terraform.tfvars")
    FIRST=$(talosctl --talosconfig "$TC" get members -o json -n "$FIRST" 2>/dev/null \
      | jq -rs '.[0].spec.addresses[0]' 2>/dev/null || echo "$FIRST")
    echo "── Version ──"
    talosctl --talosconfig "$TC" version --short -n "$FIRST"
    echo ""
    echo "── Extensions ──"
    talosctl --talosconfig "$TC" get extensions -n "$FIRST"
    echo ""
    echo "── Nodes ──"
    talosctl --talosconfig "$TC" get members -n "$FIRST"

# Compute schematic ID via Talos Image Factory API for a given env
get-schematic-id env="prod":
    curl -sf -X POST --data-binary @schematic-{{ env }}.yaml \
      https://factory.talos.dev/schematics | jq -r '.id'

# Read schematic ID from the running cluster
cluster-schematic-id:
    #!/usr/bin/env bash
    set -euo pipefail
    TC="./secrets/{{ tf_env }}/talosconfig.yaml"
    ENV_DIR="{{ tf_root }}/environments/{{ tf_env }}"
    FIRST=$(awk -F'"' '/ip/{print $2; exit}' "$ENV_DIR/terraform.tfvars")
    FIRST=$(talosctl --talosconfig "$TC" get members -o json -n "$FIRST" 2>/dev/null \
      | jq -rs '.[0].spec.addresses[0]' 2>/dev/null || echo "$FIRST")
    echo "Schematic ID ({{ tf_env }}):"
    talosctl --talosconfig "$TC" get extensions -n "$FIRST" \
      -o json | jq -r 'select(.spec.metadata.name=="schematic") | .spec.metadata.version'
