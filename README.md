# infra-homelab-talos

Terraform modules that provision a Talos Linux Kubernetes cluster on Proxmox VE. One `terraform apply` goes from bare hypervisor to a working cluster with Tailscale mesh networking.

## Architecture

```
Proxmox VE
├── talos-cp1         (control plane, L2 VIP .2.210)
├── talos-w1          (worker)
├── talos-w2          (worker)
└── talos-w3          (worker)

Terraform (proxmox/)
└── modules/talos-cluster/
    ├── Machine secrets (CA, tokens)
    ├── CP config      (L2 VIP, Tailscale)
    ├── Worker config  (Tailscale)
    ├── Bootstrap
    └── Kubeconfig     (LAN + Tailscale contexts)
```

## Structure

```
proxmox/                        # Root module
├── provider.tf                  # bpg/proxmox v0.109.0
├── main.tf                      # VMs + talos-cluster module call
├── variables.tf
├── outputs.tf                   # talosconfig, kubeconfig, kubeconfig_tailscale
└── environments/{dev,prod}/     # Per-environment node definitions and state

modules/
└── talos-cluster/               # Provider-agnostic child module
    ├── main.tf                  # Talos resources
    ├── variables.tf
    └── outputs.tf

schematic.yaml                   # Image Factory extensions list
```

## Highlights

- **Modular design** — infrastructure (VMs) and configuration (Talos/K8s) are separated; `talos-cluster` module works with any provider
- **Control plane** — single node for homelab, supports HA with 3+ nodes and L2 VIP
- **Dedicated workers** — 3 workers with 100 GB disks; workloads stay off the control plane
- **Tailscale integration** — optional MagicDNS for multi-network access with per-node kubeconfig contexts
- **Custom Talos image** — Image Factory schematic bundles `iscsi-tools`, `qemu-guest-agent`, `tailscale`, `util-linux-tools`

## Requirements

- Proxmox VE 8.x with API access
- Terraform >= 1.5
- Talos Image Factory schematic ID

## Quick start

```bash
# (Optional) enable Tailscale
export TF_VAR_tailscale_auth_key="tskey-auth-..."

# Bootstrap the cluster (auto-inits, uses prod by default)
just tf-apply

# Extract credentials and merge into local ~/.talos/config and ~/.kube/config
just setup-cli
```

All `just` commands run from the repo root. Set `tf_env=dev` to target the dev environment instead.

## Variables

### Proxmox

| Variable | Description | Default |
|----------|-------------|---------|
| `endpoint` | Proxmox API URL | — |
| `username` | Proxmox API user | — |
| `password` | Proxmox API token secret | — |
| `insecure` | Skip TLS verify | `false` |
| `gateway` | VM default gateway | — |
| `nodes_cp` | Control plane VM definitions | — |
| `nodes_worker` | Worker VM definitions | — |

### Talos

| Variable | Description | Default |
|----------|-------------|---------|
| `talos_version` | Talos version | `1.13.3` |
| `talos_image_factory_id` | Image Factory schematic ID | `077514...` |
| `tailscale_auth_key` | Tailscale auth key (env var) | `""` (opt-in) |

## Access

Use dev instead prod on dev enviroments.

```bash
# LAN (L2 VIP)
talosctl --talosconfig secrets/prod/talosconfig.yaml version

# Tailscale (per-node contexts)
kubectl --kubeconfig secrets/prod/kubeconfig.yaml get nodes
kubectl --kubeconfig secrets/prod/kubeconfig.yaml config use-context talos-cluster-0
```

## Why

Hands-on infrastructure-as-code with real hardware. Designed to be modular, reproducible, and portable.

## Available `just` tasks

| Task | Description |
|------|-------------|
| `tf-plan` | Plan changes for the target environment |
| `tf-apply` | Apply changes (bootstrap or update the cluster) |
| `tf-destroy` | Tear down the entire environment |
| `gen-secrets` | Extract talosconfig + kubeconfig from Terraform state |
| `setup-cli` | gen-secrets + merge into local `~/.talos/config` and `~/.kube/config` |
| `status` | Show Talos version, extensions, and cluster members |
| `get-schematic-id` | Compute schematic ID from `schematic.yaml` via the Image Factory API |
| `cluster-schematic-id` | Read the active schematic ID from the running cluster |

Set `tf_env=dev` for any task to target the dev environment (default: `prod`).
