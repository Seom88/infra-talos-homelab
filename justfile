# infra-homelab — Talos helper tasks
# Providers: proxmox (prod, dev) | libvirt (dev, prod)
# Terraform: ./environments/<provider>/<env>/
# Secrets: ./secrets/<provider>/<env>/
# Backend: prod S3 (RustFS), dev local
# Usage: just tf-apply (default libvirt/dev) or just provider=... env=... tf-apply
# Platform (ArgoCD) via modules/platform; single apply for infra + platform.

provider := "libvirt"   # proxmox | libvirt
env      := "dev"      # prod | dev

tf_root     := "./environments/" + provider + "/" + env
secrets_dir := "./secrets/" + provider + "/" + env
tfvars_path := tf_root + "/terraform.tfvars"
label       := provider + "/" + env

# Terraform

# Format Terraform files
tf-fmt:
    terraform fmt -recursive

# Check formatting (CI-style)
tf-fmt-check:
    terraform fmt -check -diff -recursive

# Validate all envs (no backend)
tf-validate:
    #!/usr/bin/env bash
    set -euo pipefail
    for env in proxmox/prod proxmox/dev libvirt/prod libvirt/dev; do
      echo "── Validate $env ──"
      terraform -chdir=environments/$env init -backend=false -no-color
      terraform -chdir=environments/$env validate -no-color
    done
    echo "── Validate modules/platform ──"
    terraform -chdir=modules/platform init -backend=false -no-color
    terraform -chdir=modules/platform validate -no-color

# Full CI check (fmt + validate)
tf-ci:
    just tf-fmt-check
    just tf-validate

# Init
tf-init:
    terraform -chdir={{ tf_root }} init -reconfigure

# Plan
tf-plan:
    terraform -chdir={{ tf_root }} fmt
    terraform -chdir={{ tf_root }} init -reconfigure
    terraform -chdir={{ tf_root }} plan

# Apply (parallelism 10)
tf-apply:
    terraform -chdir={{ tf_root }} fmt
    terraform -chdir={{ tf_root }} init -reconfigure
    terraform -chdir={{ tf_root }} apply -parallelism=10

# Apply for upgrades (parallelism 1, protects quorum)
tf-apply-upgrade:
    terraform -chdir={{ tf_root }} fmt
    terraform -chdir={{ tf_root }} init -reconfigure
    terraform -chdir={{ tf_root }} apply -parallelism=1

# Destroy
tf-destroy:
    #!/usr/bin/env bash
    set -euo pipefail
    terraform -chdir={{ tf_root }} init -reconfigure
    # Skip health gate on destroy
    TF_VAR_enable_health_check=false terraform -chdir={{ tf_root }} destroy

# Secrets

# Generate secrets from state
gen-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    SECRETS="{{ secrets_dir }}"
    mkdir -p "$SECRETS"
    terraform -chdir={{ tf_root }} init -reconfigure
    terraform -chdir={{ tf_root }} output -raw talosconfig > "$SECRETS/talosconfig.yaml"
    terraform -chdir={{ tf_root }} output -raw kubeconfig  > "$SECRETS/kubeconfig.yaml"
    echo "✓ secrets regenerated ({{ label }})"

# Merge secrets into local configs
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

# Cluster status
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

# Compute schematic ID via factory API
get-schematic-id name="prod":
    curl -sf -X POST --data-binary @schematic-{{ name }}.yaml \
      https://factory.talos.dev/schematics | jq -r '.id'

# Read schematic ID from cluster
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

# Host prerequisites (libvirt): ensure firewalld NAT for talos-net
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
