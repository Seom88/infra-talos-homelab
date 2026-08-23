# ──────────────────────────────────────────────
#  infra-homelab — Talos helper tasks
# ──────────────────────────────────────────────
#  All commands run from the repo root.
#
#  Providers:  proxmox (envs: prod, dev)  |  libvirt (no envs)
#  Terraform:  {{ tf_root }}/    (./proxmox or ./libvirt)
#  Secrets:    ./secrets/<env-or-provider>/   (.gitignored)
#
#  Usage:
#    just tf-apply                              # proxmox, prod (default)
#    just provider=proxmox tf_env=dev tf-apply  # proxmox, dev
#    just provider=libvirt tf-apply             # libvirt (no env)
#
#  Platform (ArgoCD) does NOT depend on provider/env: it applies to
#  the kubeconfig context that is active at that moment.
#    just setup-cli           # point kubectl/talosctl at a cluster
#    just tf-platform-apply   # installs ArgoCD there

provider := "proxmox"   # proxmox | libvirt
tf_env   := "prod"      # only applies when provider == proxmox

tf_root      := if provider == "proxmox" { "./proxmox" } else { "./libvirt" }
env_dir      := if provider == "proxmox" { tf_root + "/environments/" + tf_env } else { tf_root }
secrets_dir  := if provider == "proxmox" { "./secrets/" + tf_env } else { "./secrets/libvirt" }
backend_arg  := if provider == "proxmox" { "-backend-config=path=environments/" + tf_env + "/terraform.tfstate" } else { "" }
var_file_arg := if provider == "proxmox" { "-var-file=environments/" + tf_env + "/terraform.tfvars" } else { "" }
tfvars_path  := env_dir + "/terraform.tfvars"
label        := if provider == "proxmox" { provider + "/" + tf_env } else { provider }

# ── Terraform (proxmox or libvirt, per `provider=`) ───────────

# Format all Terraform files recursively
tf-fmt:
    terraform fmt -recursive

# Init terraform with local backend for the active provider/env
tf-init:
    terraform -chdir={{ tf_root }} init -reconfigure {{ backend_arg }}

# Plan changes (auto-init to ensure the correct backend)
tf-plan:
    terraform -chdir={{ tf_root }} fmt
    terraform -chdir={{ tf_root }} init -reconfigure {{ backend_arg }}
    terraform -chdir={{ tf_root }} plan {{ var_file_arg }}

# Apply changes (auto-init to ensure the correct backend).
# IaC upgrades via var.talos_version use talos_machine.image — those reboots
# must be sequential to protect etcd quorum, so we serialize. Bootstrap from
# scratch will be slower (15m x3) but safe; remove `-parallelism=1` if you
# want fast parallel bootstrap and accept parallel upgrade risk.
tf-apply:
    terraform -chdir={{ tf_root }} fmt
    terraform -chdir={{ tf_root }} init -reconfigure {{ backend_arg }}
    terraform -chdir={{ tf_root }} apply {{ var_file_arg }} -parallelism=1

# Destroy the active provider/env (auto-init for the correct backend)
tf-destroy:
    #!/usr/bin/env bash
    set -euo pipefail
    # Clean up Tailscale devices before destroy
    if [[ -n "${TS_OAUTH_CLIENT_ID:-}" && -n "${TS_OAUTH_SECRET:-}" ]]; then
      ./scripts/destroy-tailscale-devices.sh \
        {{ tfvars_path }} lonk-mirfak || \
        echo "⚠ Tailscale cleanup failed, continuing with destroy"
    fi
    terraform -chdir={{ tf_root }} init -reconfigure {{ backend_arg }}
    terraform -chdir={{ tf_root }} destroy {{ var_file_arg }}

# ── Secrets ────────────────────────────────────

# Generate talosconfig + kubeconfig from terraform state
gen-secrets:
    #!/usr/bin/env bash
    set -euo pipefail
    SECRETS="{{ secrets_dir }}"
    mkdir -p "$SECRETS"
    terraform -chdir={{ tf_root }} init -reconfigure {{ backend_arg }}
    terraform -chdir={{ tf_root }} output -raw talosconfig > "$SECRETS/talosconfig.yaml"
    terraform -chdir={{ tf_root }} output -raw kubeconfig  > "$SECRETS/kubeconfig.yaml"
    echo "✓ secrets regenerated ({{ label }})"

# Merge secrets into local talosctl and kubectl config
setup-cli:
    #!/usr/bin/env bash
    set -euo pipefail
    just provider="{{ provider }}" tf_env="{{ tf_env }}" gen-secrets
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

# ── Platform (ArgoCD) — agnostic of provider/env ───────────────
# Applies to the active kubeconfig context (run `setup-cli`
# pointing at whichever cluster you want before using these commands).

platform_root := "./platform"

tf-platform-init:
    terraform -chdir={{ platform_root }} init -reconfigure

tf-platform-plan:
    terraform -chdir={{ platform_root }} fmt
    terraform -chdir={{ platform_root }} init -reconfigure
    terraform -chdir={{ platform_root }} plan

tf-platform-apply:
    terraform -chdir={{ platform_root }} fmt
    terraform -chdir={{ platform_root }} init -reconfigure
    terraform -chdir={{ platform_root }} apply

tf-platform-destroy:
    terraform -chdir={{ platform_root }} init -reconfigure
    terraform -chdir={{ platform_root }} destroy

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
