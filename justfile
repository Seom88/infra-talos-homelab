# infra-homelab — Talos helper tasks
# Providers: proxmox (prod, dev) | libvirt (dev, prod)
# Terraform: ./environments/<provider>/<env>/
# Secrets: ./secrets/<provider>/<env>/
# Backend: prod S3 (RustFS), dev local
# Usage: just tf-apply (default libvirt/dev) or just provider=... env=... tf-apply
# Platform (ArgoCD) via modules/platform; single apply for infra + platform.

provider := "proxmox"   # proxmox | libvirt
env      := "prod"      # prod | dev

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

# Read schematic ID from Terraform state (canonical extension set in modules/talos-image)
get-schematic-id:
    terraform -chdir={{ tf_root }} output -raw schematic_id

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

# Apply CPU affinity + cpuunits as root (API tokens cannot set affinity)
# Source of truth: environments/proxmox/prod/terraform.tfvars (cpu_affinity/cpu_units per node).
# VMIDs are resolved by hostname at runtime — never hardcoded. Only tfvars
# hostnames are touched, so non-Talos VMs (e.g. TrueNAS) are never affected.
# Idempotent: qm set converges to the tfvars values; safe to re-run.
affinity-sync:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ provider }}" != "proxmox" ]; then
      echo "affinity-sync is proxmox-only (provider={{ provider }}); run with just provider=proxmox env=prod affinity-sync"
      exit 1
    fi
    TFVARS="{{ tfvars_path }}"
    SSH_HOST=$(grep -E '^\s*ssh_node_address' "$TFVARS" | head -n1 | sed -E 's/.*=\s*"([^"]+)".*/\1/')
    SSH_HOST=${SSH_HOST:-pve01}
    echo "── affinity-sync from $TFVARS via root@$SSH_HOST ──"
    python3 - "$TFVARS" > /tmp/affinity-sync.map <<'EOF'
    import re, sys
    host = affinity = units = None
    rows = []
    def flush():
        if host and affinity:
            rows.append((host, affinity, units or ""))
    with open(sys.argv[1]) as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            m = re.match(r'hostname\s*=\s*"([^"]+)"', s)
            if m:
                flush(); host, affinity, units = m.group(1), None, None
                continue
            m = re.match(r'cpu_affinity\s*=\s*"([^"]+)"', s)
            if m:
                affinity = m.group(1)
                continue
            m = re.match(r'cpu_units\s*=\s*(\d+)', s)
            if m:
                units = m.group(1)
    flush()
    for r in rows:
        print(f"{r[0]} {r[1]} {r[2]}")
    EOF
    while read -r HOST AFFINITY UNITS; do
      [ -z "$HOST" ] && continue
      echo "── $HOST (affinity=$AFFINITY cpuunits=${UNITS:-unchanged}) ──"
      VMID=$(ssh -n -o BatchMode=yes "root@$SSH_HOST" 'qm list' | awk -v name="$HOST" '$2==name {print $1}')
      if [ -z "$VMID" ]; then echo "✗ no VMID found for $HOST; skipping"; continue; fi
      echo "resolved $HOST -> VMID $VMID"
      ARGS="--affinity $AFFINITY"
      if [ -n "$UNITS" ]; then ARGS="$ARGS --cpuunits $UNITS"; fi
      # shellcheck disable=SC2086
      ssh -n -o BatchMode=yes "root@$SSH_HOST" "qm set $VMID $ARGS"
      ssh -n -o BatchMode=yes "root@$SSH_HOST" "qm config $VMID" | grep -E '^(affinity|cpuunits):' || true
    done < /tmp/affinity-sync.map
    rm -f /tmp/affinity-sync.map
    echo "✓ affinity-sync done ({{ label }})"

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
