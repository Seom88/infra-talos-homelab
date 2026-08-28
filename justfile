# ──────────────────────────────────────────────
#  infra-homelab — Talos helper tasks
# ──────────────────────────────────────────────
#  All commands run from the repo root.
#
#  Providers:  proxmox (envs: prod, dev)  |  libvirt (envs: dev, prod)
#  Terraform:  ./environments/<provider>/<env>/
#  Secrets:    ./secrets/<provider>/<env>/   (.gitignored)
#
#  Backend: prod uses S3 (RustFS) via environments/<provider>/prod/provider.tf.
#           Both justfile and CI use `terraform init -reconfigure` with
#           AWS_* env vars (see .github/workflows/deploy.yaml). No extra
#           -backend-config needed — bucket/key are in provider.tf.
#           Dev uses backend \"local\" — no credentials required.
#
#  Usage:
#    just tf-apply                               # proxmox, prod (default)
#    just provider=proxmox env=dev tf-apply      # proxmox, dev
#    just provider=libvirt env=dev tf-apply      # libvirt, dev (local only)
#
#  Platform (ArgoCD) is now a composable module (modules/platform) called from
#  each environment root (environments/<provider>/<env>). One `terraform apply`
#  deploys both infra and platform (single state at
#  environments/<provider>/<env>/terraform.tfstate). The standalone
#  platform/ root is deprecated — see platform/DEPRECATED.md.
#    just provider=proxmox env=prod setup-cli           # point kubectl/talosctl at proxmox/prod
#    just provider=proxmox env=prod tf-apply            # infra + platform (ArgoCD) in one apply

provider := "proxmox"   # proxmox | libvirt
env      := "prod"      # prod | dev

tf_root     := "./environments/" + provider + "/" + env
secrets_dir := "./secrets/" + provider + "/" + env
tfvars_path := tf_root + "/terraform.tfvars"
label       := provider + "/" + env

# ── Terraform (proxmox or libvirt, per `provider=` / `env=`) ──

# Format all Terraform files recursively
tf-fmt:
    terraform fmt -recursive

# Init terraform with local backend for the active provider/env
tf-init:
    terraform -chdir={{ tf_root }} init -reconfigure

# Plan changes (auto-init to ensure the correct backend)
tf-plan:
    terraform -chdir={{ tf_root }} fmt
    terraform -chdir={{ tf_root }} init -reconfigure
    terraform -chdir={{ tf_root }} plan

# Apply changes (auto-init to ensure the correct backend).
# C: parallel 10 for bootstrap, use tf-apply-upgrade for talos_version bumps
tf-apply:
    terraform -chdir={{ tf_root }} fmt
    terraform -chdir={{ tf_root }} init -reconfigure
    terraform -chdir={{ tf_root }} apply -parallelism=10

# Apply with sequential parallelism for talos_version upgrades (protects etcd quorum)
tf-apply-upgrade:
    terraform -chdir={{ tf_root }} fmt
    terraform -chdir={{ tf_root }} init -reconfigure
    terraform -chdir={{ tf_root }} apply -parallelism=1

# Destroy the active provider/env (auto-init for the correct backend)
tf-destroy:
    #!/usr/bin/env bash
    set -euo pipefail
    terraform -chdir={{ tf_root }} init -reconfigure
    # Health gate would otherwise block destroy when cluster is already unhealthy / you want to start from zero
    TF_VAR_enable_health_check=false terraform -chdir={{ tf_root }} destroy

# ── Secrets ────────────────────────────────────

# Generate talosconfig + kubeconfig from terraform state
gen-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    SECRETS="{{ secrets_dir }}"
    mkdir -p "$SECRETS"
    terraform -chdir={{ tf_root }} init -reconfigure
    terraform -chdir={{ tf_root }} output -raw talosconfig > "$SECRETS/talosconfig.yaml"
    terraform -chdir={{ tf_root }} output -raw kubeconfig  > "$SECRETS/kubeconfig.yaml"
    echo "✓ secrets regenerated ({{ label }})"

# Merge secrets into local talosctl and kubectl config
setup-cli:
    #!/usr/bin/env bash
    set -euo pipefail
    just provider="{{ provider }}" env="{{ env }}" gen-secrets
    SECRETS="{{ secrets_dir }}"
    TC="$SECRETS/talosconfig.yaml"
    KC="$SECRETS/kubeconfig.yaml"
    # talosctl
    mkdir -p ~/.talos
    if [[ -f ~/.talos/config ]]; then
        talosctl config merge "$TC"
    else
        cp "$TC" ~/.talos/config
    fi
    echo "✓ talosctl configured ({{ label }})"
    # kubectl
    mkdir -p ~/.kube
    KUBECONFIG="$KC":~/.kube/config \
      kubectl config view --flatten > /tmp/kube-merge
    mv /tmp/kube-merge ~/.kube/config
    echo "✓ kubectl configured ({{ label }})"

# ── Cluster Status ─────────────────────────────

# Show Talos version, extensions, and nodes (active provider/env)
status:
    #!/usr/bin/env bash
    set -euo pipefail
    TC="{{ secrets_dir }}/talosconfig.yaml"
    FIRST=$(awk -F'"' '/ip/{print $2; exit}' "{{ tfvars_path }}")
    FIRST=$(talosctl --talosconfig "$TC" get members -o json -n "$FIRST" 2>/dev/null \
      | jq -rs '.[0].spec.addresses[0]' 2>/dev/null || echo "$FIRST")
    echo "── Version ({{ label }}) ──"
    talosctl --talosconfig "$TC" version --short -n "$FIRST"
    echo ""
    echo "── Extensions ──"
    talosctl --talosconfig "$TC" get extensions -n "$FIRST"
    echo ""
    echo "── Nodes ──"
    talosctl --talosconfig "$TC" get members -n "$FIRST"

# Compute schematic ID via Talos Image Factory API (schematic-<name>.yaml)
get-schematic-id name="prod":
    curl -sf -X POST --data-binary @schematic-{{ name }}.yaml \
      https://factory.talos.dev/schematics | jq -r '.id'

# Read schematic ID from the running cluster (active provider/env)
cluster-schematic-id:
    #!/usr/bin/env bash
    set -euo pipefail
    TC="{{ secrets_dir }}/talosconfig.yaml"
    FIRST=$(awk -F'"' '/ip/{print $2; exit}' "{{ tfvars_path }}")
    FIRST=$(talosctl --talosconfig "$TC" get members -o json -n "$FIRST" 2>/dev/null \
      | jq -rs '.[0].spec.addresses[0]' 2>/dev/null || echo "$FIRST")
    echo "Schematic ID ({{ label }}):"
    talosctl --talosconfig "$TC" get extensions -n "$FIRST" \
      -o json | jq -r 'select(.spec.metadata.name=="schematic") | .spec.metadata.version'

# ── Host Prerequisites (libvirt) ───────
# Ensures firewalld NAT for talos-net (virbr-talos) - required for Talos image pulls (factory.talos.dev).
# libvirt_network with forward nat + bridge.zone=libvirt creates the network, but host firewalld must have masquerade.
# Run once per hypervisor host (needs sudo/polkit). Idempotent.
setup-host:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Ensuring firewalld masquerade/forward for libvirt zone..."
    if ! firewall-cmd --zone=libvirt --query-masquerade >/dev/null 2>&1; then
      echo "Enabling masquerade..."
      sudo firewall-cmd --zone=libvirt --add-masquerade --permanent || pkexec firewall-cmd --zone=libvirt --add-masquerade --permanent
      sudo firewall-cmd --zone=libvirt --add-masquerade || pkexec firewall-cmd --zone=libvirt --add-masquerade || true
    fi
    if ! firewall-cmd --zone=libvirt --query-forward >/dev/null 2>&1; then
      sudo firewall-cmd --zone=libvirt --add-forward --permanent || pkexec firewall-cmd --zone=libvirt --add-forward --permanent || true
      sudo firewall-cmd --zone=libvirt --add-forward || pkexec firewall-cmd --zone=libvirt --add-forward || true
    fi
    sudo firewall-cmd --reload 2>/dev/null || pkexec firewall-cmd --reload 2>/dev/null || true
    firewall-cmd --zone=libvirt --query-masquerade && echo "✓ masquerade: yes" || echo "✗ masquerade still no"
    firewall-cmd --zone=libvirt --query-forward && echo "✓ forward: yes" || echo "✗ forward still no"
