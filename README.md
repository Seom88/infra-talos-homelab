# infra-homelab — Talos Kubernetes on Proxmox with Terraform

Provision a Kubernetes cluster (Talos Linux) on Proxmox VE using Terraform modules — 1 control plane + 3 workers, designed for HA with additional CP nodes. Tailscale-enabled for secure access across networks.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Proxmox VE                            │
│  ┌────────────┐  ┌───────────┐  ┌───────────┐  ┌────────┐ │
│  │ talos-cp1   │  │ talos-cp2 │  │ talos-cp3 │  │ ...    │ │
│  │ (control    │  │ (control  │  │ (control  │  │ (HA)   │ │
│  │  plane)     │  │  plane)   │  │  plane)   │  │        │ │
│  └──────┬──────┘  └─────┬─────┘  └─────┬─────┘  └───┬────┘ │
│         │               │               │            │      │
│         └───────┬───────┴───────┬───────┘            │      │
│                 │               │                     │      │
│            ┌────┴─────┐   ┌────┴──────┐               │      │
│            │ L2 VIP   │   │  etcd     │               │      │
│            │  .2.210   │   │ (CP only) │               │      │
│            └────┬─────┘   └───────────┘               │      │
│                 │                                      │      │
│                 │                                      │      │
│  ┌────────────┐ │ ┌───────────┐ ┌───────────┐ ┌───────┴───┐ │
│  │ talos-w1   │ │ │ talos-w2  │ │ talos-w3  │ │ ...       │ │
│  │ (worker)   │ │ │ (worker)  │ │ (worker)  │ │ (scale)   │ │
│  └──────┬─────┘ │ └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ │
│         │       │       │             │             │       │
│         └───┬───┴───┬───┴──────┬──────┘             │       │
│             │       │          │                      │      │
│        ┌────┴────┐  │    ┌────┴────┐                  │      │
│        │ Tailscale│  │    │ MagicDNS│                  │      │
│        │ (secure  │  │    │ (multi- │                  │      │
│        │  access) │  │    │ network)│                  │      │
│        └─────────┘  │    └─────────┘                  │      │
└──────────────────────────────────────────────────────────────┘
         │
         │ terraform apply
         ▼
┌──────────────────────────────────────────┐
│         Terraform (proxmox/)             │
│  ┌────────────────────────────────────┐  │
│  │  talos-cluster module              │  │
│  │  - Machine secrets                 │  │
│  │  - CP + Worker configs             │  │
│  │  - Bootstrap                       │  │
│  │  - Kubeconfig (standard + Tailscale)│  │
│  └────────────────────────────────────┘  │
└──────────────────────────────────────────┘
```

## Structure

```
proxmox/                        # Root module
├── provider.tf                  # bpg/proxmox provider
├── main.tf                      # VMs + talos-cluster module call
├── variables.tf                 # All root variables
├── outputs.tf                   # talosconfig, kubeconfig, kubeconfig_tailscale
├── terraform.tfvars             # Environment config (IPs, nodes, storage)
└── secret.auto.tfvars           # Proxmox credentials

modules/
└── talos-cluster/               # Reusable child module
    ├── main.tf                  # Talos resources (secrets, config, bootstrap)
    ├── variables.tf             # Talos-specific variables
    └── outputs.tf               # talosconfig, kubeconfig, kubeconfig_tailscale

schematic.yaml                   # Talos Image Factory extensions
```

## Highlights

| Area | What it does |
|------|-------------|
| **Terraform modules** | `talos-cluster` is fully reusable — works with any provider that gives you VMs and IPs |
| **Control plane** | Single node (homelab) — designed for HA with 3+ nodes; L2 VIP |
| **Dedicated workers** | 3 worker nodes, 100 GB disk each — workloads stay off the CP |
| **Tailscale integration** | Optional MagicDNS for multi-network access, with per-node kubeconfig contexts |
| **Custom Talos image** | Image Factory schematic with extensions (iscsi-tools, qemu-guest-agent, tailscale, util-linux) |

## Requirements

- Proxmox VE 8.x
- Terraform 1.x
- [Talos Image Factory](https://factory.talos.dev) schematic ID

## Quick start

```bash
# 1. Set Tailscale auth key (optional — skip if you don't need Tailscale)
export TF_VAR_tailscale_auth_key="tskey-auth-..."

# 2. Bootstrap the cluster
cd proxmox
terraform init && terraform apply

# 3. Extract credentials (or use `just gen-secrets` later)
terraform output -raw talosconfig > ../secrets/talosconfig.yaml
terraform output -raw kubeconfig  > ../secrets/kubeconfig.yaml

# 4. Merge into local config
just setup-cli
```

> All `just` commands run from the repo root. See `justfile` for available tasks.

## Variables

### Proxmox

| Variable | Description | Default |
|----------|-------------|---------|
| `username` | Proxmox API user | — |
| `password` | Proxmox API token secret | — |
| `endpoint` | Proxmox API URL | — |
| `insecure` | Skip TLS verify | `false` |
| `gateway` | VM default gateway | — |
| `nodes_cp` | List of control plane VM definitions | — |
| `nodes_worker` | List of worker VM definitions | — |

### Talos

| Variable | Description | Default |
|----------|-------------|---------|
| `talos_version` | Talos version | `1.13.3` |
| `talos_image_factory_id` | Image Factory schematic ID | `077514...` |
| `tailscale_auth_key` | Tailscale auth key (env var) | `""` (opt-in) |

## Access

```bash
# Via LAN (L2 VIP)
talosctl --talosconfig secrets/talosconfig.yaml version

# Via Tailscale (per-node contexts)
kubectl --kubeconfig secrets/kubeconfig.yaml get nodes
kubectl --kubeconfig secrets/kubeconfig.yaml config use-context talos-cluster-0
```

## Why this exists

This is a hands-on Terraform project to practice infrastructure-as-code with real hardware. It's designed to be:

- **Modular** — separate concerns between infrastructure (VMs) and configuration (Talos/K8s)
- **Reproducible** — one `terraform apply` from bare Proxmox to a working cluster
- **Portable** — the `talos-cluster` module is provider-agnostic

---

*Built with Terraform, Talos Linux, and Proxmox.*
