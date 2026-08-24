# infra-talos-homelab

![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5-7B42BC?logo=terraform)
![Talos](https://img.shields.io/badge/Talos_Linux-1.13-000000?logo=linux)
![License](https://img.shields.io/badge/License-MIT-green)
![CI](https://img.shields.io/github/actions/workflow/status/Seom88/infra-talos-homelab/deploy.yaml?label=CI)

Terraform modules that provision a Talos Linux Kubernetes cluster on **Proxmox VE** (via `bpg/proxmox`) or **libvirt** (via `dmacvicar/libvirt`). One `terraform apply` goes from bare hypervisor or host to a working cluster with Tailscale mesh networking.

![Demo](docs/demo.png)

## Architecture

### Proxmox provider

```
Proxmox VE
├── N × control plane nodes  (L2 VIP shared, Tailscale in prod)
└── M × worker nodes         (Tailscale in prod)

Terraform (proxmox/)
├── Per-env backend          (environments/{dev,prod}/terraform.tfstate)
├── Per-env tfvars           (environments/{dev,prod}/terraform.tfvars)
├── Image download           (proxmox_download_file from Image Factory)
├── VMs                      (proxmox_virtual_environment_vm per node)
└── modules/talos-cluster/
    ├── Bootstrap
    └── Kubeconfig           (LAN + Tailscale contexts)
```

### Libvirt provider

```
Libvirt (qemu:///system)
├── talos-cp1         (control plane, L2 VIP 10.0.1.10)
├── talos-w1          (worker)
├── talos-w2          (worker)
└── talos-w3          (worker)

Terraform (libvirt/)
├── NAT network       (10.0.1.0/24, DHCP from node MACs)
├── Image cache       (nocloud raw image from Image Factory)
├── Boot volumes      (one raw volume per node)
├── Cloud-init        (static IPs, Talos machine config as user-data)
└── modules/talos-cluster/
    ├── Bootstrap
    └── Kubeconfig     (LAN + Tailscale contexts)
```

## Structure

```
.github/
└── workflows/
    ├── deploy.yaml                 # CI/CD: automated Terraform apply
    └── destroy.yaml                # CI/CD: tear down cluster + Tailscale cleanup

scripts/
└── destroy-tailscale-devices.sh    # Pre-destroy Tailscale device cleanup

proxmox/                        # Proxmox VE root module
├── provider.tf                  # bpg/proxmox v0.109.0
├── main.tf                      # Image download, VMs, talos module call
├── variables.tf                 # Proxmox + pass-through vars
├── outputs.tf                   # talosconfig, kubeconfig, kubeconfig_tailscale
└── environments/
    ├── dev/
    │   ├── terraform.tfvars      # Dev node definitions (3 cp, optional workers)
    │   └── terraform.tfstate     # Per-env local backend state
    └── prod/
        └── terraform.tfvars      # Prod node definitions (3 cp, optional workers)

libvirt/                        # Libvirt root module
├── provider.tf                  # dmacvicar/libvirt ~> 0.9.8 + siderolabs/talos ~> 0.11
├── main.tf                      # NAT network, boot volumes, cloud-init, VMs, talos-cluster
├── variables.tf                 # Node definitions, network, schematic, pass-through vars
├── outputs.tf                   # talosconfig, kubeconfig, kubeconfig_tailscale
└── terraform.tfvars             # Node IPs, MACs, specs

environments/                  # Composed roots (infra + platform in one state)
├── proxmox/{prod,dev}/         # bpg/proxmox + helm provider + module.platform
└── libvirt/{prod,dev}/         # dmacvicar/libvirt + helm provider + module.platform

platform/                       # DEPRECATED standalone root (kept for state migration)
├── DEPRECATED.md               # Migration guide (terraform state mv)
├── main.tf                     # (deprecated) Node readiness gate + ArgoCD Helm chart
├── providers.tf                # (deprecated) helm provider
└── values/argocd/              # (deprecated) duplicate — canonical is modules/platform/values

modules/
├── talos-cluster/               # Provider-agnostic child module
│   ├── main.tf                  # Talos resources (bootstrap, kubeconfig)
│   ├── variables.tf
│   └── outputs.tf
└── platform/                    # Composable platform module (ArgoCD)
    ├── main.tf                  # Node readiness gate + ArgoCD Helm chart (no backend)
    ├── variables.tf             # kubeconfig_path, argocd_version, argocd_namespace
    ├── outputs.tf
    └── values/argocd/           # ArgoCD Helm values (canonical)

schematic-dev.yaml               # Dev Image Factory extensions
schematic-prod.yaml              # Prod Image Factory extensions
LICENSE                          # MIT License
secrets/                         # Generated credentials (.gitignored)
└── <provider>/<env>/            # e.g. proxmox/prod, libvirt/dev — talosconfig.yaml, kubeconfig.yaml
```

## Highlights

- **Two providers** — choose Proxmox VE (`bpg/proxmox`) or libvirt (`dmacvicar/libvirt`); both share the same provider-agnostic `talos-cluster` module
- **Modular design** — infrastructure (VMs) and configuration (Talos/K8s) are separated; `talos-cluster` module works with any provider
- **Control plane** — 1–3 nodes with L2 VIP; HA with 3+ nodes. Proxmox prod runs 3 CP nodes, dev runs 1
- **Dedicated workers** — worker VMs keep workloads off the control plane; disk sizes configurable per node (20 GB CP default, 100 GB worker default)
- **Tailscale integration** — optional MagicDNS for multi-network access with per-node kubeconfig contexts
- **Longhorn-ready** — kubelet extraMounts for `/var/lib/longhorn` injected by default on all nodes; system extensions (`iscsi-tools`, `util-linux-tools`) bundled in the Image Factory schematic
- **Image caching (libvirt)** — nocloud raw images are downloaded, cached, and reused across applies; only the first apply downloads
- **NAT networking (libvirt)** — dedicated `virbr-talos` bridge with DHCP reservations and DNS entries from node MACs
- **Custom Talos image** — Image Factory schematic bundles `iscsi-tools`, `qemu-guest-agent`, `tailscale`, `util-linux-tools`
- **In-place Talos upgrades** — `talos_machine` keeps the OS version in sync via `image`; bumping `talos_version` triggers a sequential rolling upgrade (pull → install → reboot) with `drain_on_upgrade = false` and `-parallelism=1`, so etcd quorum is protected without VM recreation. Installer images are platform-aware (`nocloud-installer-secureboot` by default, `nocloud-installer` override for libvirt)

## Requirements

- **Proxmox path**: Proxmox VE 8.x with API access
- **Network access (Proxmox SDN)**: the machine running `terraform apply` (laptop or CI) must be able to reach the cluster subnet `10.10.0.0/24`. The `talosvn` SDN VNet is isolated — VMs get outbound internet via SNAT but nothing from outside reaches them directly. For `prod`, expose the subnet through a Tailscale subnet router (see [Quick start → Proxmox](#proxmox-1))
- **Libvirt path**: Linux host with libvirt + KVM and `qemu:///system` accessible
- Terraform >= 1.5
- Talos Image Factory schematic ID

## How it works

```mermaid
flowchart TD
    A[terraform apply] --> B[Image Factory API]
    B --> C[Download Talos raw image]
    C --> D{Provider?}

    D -->|Proxmox| E[Create VMs via Proxmox API]
    D -->|libvirt| F[Create boot volumes + cloud-init]

    E --> G[VM boots Talos]
    F --> G

    G --> H[Talos bootstrap]
    H --> I[Control plane ready]
    I --> J[Generate kubeconfig + talosconfig]

    J --> K{Tailscale enabled?}
    K -->|Yes| L[Per-node Tailscale contexts]
    K -->|No| M[LAN-only contexts]

    L --> N[kubectl / talosctl ready]
    M --> N
```

**Proxmox path**: Terraform talks to the Proxmox API to download the Talos image and create VMs with cloud-init. Talos boots, the cluster bootstraps, and kubeconfig is generated with both LAN (VIP) and Tailscale contexts.

**Libvirt path**: Terraform downloads the nocloud raw image, creates boot volumes, and injects cloud-init with static IPs and Talos machine config. VMs boot via libvirt, the cluster bootstraps, and kubeconfig is generated.

Both paths share the same `talos-cluster` module for bootstrap and kubeconfig generation.

## Quick start

### Proxmox

```bash
# (Optional) enable Tailscale for prod
export TF_VAR_tailscale_auth_key="tskey-auth-..."

# Bootstrap the prod cluster (default env)
just tf-apply

# Or target the dev environment
just provider=proxmox env=dev tf-apply

# Extract credentials and merge into local config
just setup-cli                         # proxmox/prod (default)
just provider=proxmox env=dev setup-cli  # proxmox/dev
```

All `just` commands run from the repo root. Each environment has its own `terraform.tfvars`, backend state at `environments/<provider>/<env>/terraform.tfstate` (single file now includes both infra and platform via `module.platform`), and secrets at `secrets/<provider>/<env>/`. Tailscale is only enabled for `prod`.

> **Network reachability (Proxmox SDN)**: Terraform must be able to reach the cluster IPs (`10.10.0.0/24`). The `talosvn` SDN VNet is isolated — VMs get outbound internet via SNAT (subnet `snat = true`), but traffic from outside cannot reach them directly. If you are not on the same network as the Proxmox host, expose the subnet through Tailscale from the Proxmox node (prod):
>
> ```bash
> # 1. On the Proxmox host (subnet router — it already runs Tailscale)
> sudo tailscale set --advertise-routes=10.10.0.0/24
> ```
>
> 2. Approve the route: admin console → **Machines** → the host row → **Subnets** → **Edit route settings** → tick `10.10.0.0/24` → **Save**
> 3. On the device running Terraform: `sudo tailscale set --accept-routes` (Linux only — Windows/macOS accept routes by default)
>
> Without the route, the `talos_cluster_health` gate waits until its 15 m timeout because it cannot reach the control plane endpoints.

### Libvirt

```bash
# (Optional) enable Tailscale
export TF_VAR_tailscale_auth_key="tskey-auth-..."

# Bootstrap the cluster
just provider=libvirt tf-apply

# Extract credentials and merge into local ~/.talos/config and ~/.kube/config
just provider=libvirt setup-cli
```

## Variables

### Proxmox

| Variable | Description | Default |
|----------|-------------|---------|
| `env_name` | Environment name (`dev` / `prod`); selects schematic file, enables Tailscale on prod | — |
| `endpoint` | Proxmox API URL (e.g. `https://10.10.10.1:8006`) | — |
| `api_token` | Proxmox API token in format `user@realm!tokenid=secret` | — |
| `username` | Proxmox API user — legacy, commented out in code | — |
| `password` | Proxmox API password — legacy, commented out in code | — |
| `ssh_username` | SSH user for Proxmox node operations | `root` |
| `ssh_node_address` | SSH address for the Proxmox node (e.g. Tailscale hostname) | — |
| `insecure` | Skip TLS verification | `false` |
| `node_name` | Proxmox node for image download | — |
| `gateway` | VM default gateway | — |
| `network_bridge` | Proxmox network bridge (e.g. `vmbr0`, `vnet1`) | `vmbr0` |
| `datastore_iso` | Datastore for ISO/raw images | `local` |
| `cluster_vip` | Virtual IP for the Kubernetes API endpoint | — |
| `nodes_cp` | Control plane nodes (hostname, ip, cores, memory, proxmox_node, disk_size, datastore, allow_scheduling — all required) | — |
| `nodes_worker` | Worker nodes (hostname, ip, cores, memory, proxmox_node, disk_size, datastore — all required) | — |
| `tailscale_domain` | Tailscale MagicDNS domain | `tail-scale.ts.net` |

### Libvirt

| Variable | Description | Default |
|----------|-------------|---------|
| `nodes_cp` | Control plane nodes (hostname, ip, mac, cores, memory, disk_size, pool, allow_scheduling — all required) | — |
| `nodes_worker` | Worker nodes (hostname, ip, mac, cores, memory, disk_size, pool — all required) | — |
| `gateway` | Default gateway IPv4 | `10.0.1.1` |
| `network_prefix` | CIDR prefix length | `24` |
| `schematic_name` | Schematic YAML filename | `schematic-dev.yaml` |
| `talos_image_cache_dir` | Local cache for nocloud raw images | `/tmp/talos-images` |
| `cluster_name` | Talos / Kubernetes cluster name | `talos-cluster` |
| `cluster_vip` | Virtual IP for the Kubernetes API endpoint | — |
| `talos_version` | Talos Linux version | `1.13.8` |
| `kubernetes_version` | Kubernetes version | `1.36.2` |
| `tailscale_auth_key` | Tailscale auth key (empty = skip) | `""` |
| `tailscale_domain` | Tailscale MagicDNS domain | — |
| `longhorn_enabled` | Inject kubelet extraMounts for Longhorn | `true` |
| `extra_config_patches` | Additional Talos machine config patches | `[]` |

### Shared

| Variable | Providers | Description | Default |
|----------|-----------|-------------|---------|
| `talos_version` | both | Talos Linux version | `1.13.9` (Proxmox default; libvirt default `1.13.8`) |
| `cluster_vip` | both | Virtual IP for the Kubernetes API endpoint | — |
| `tailscale_auth_key` | both | Tailscale auth key (empty = skip) | `""` (opt-in) |
| `installer_image` | module | Installer container image for `talos_machine.image` (e.g. `factory.talos.dev/nocloud-installer/<schematic-id>:v<version>`). Must match platform flavor — secureboot roots can omit (defaults to `nocloud-installer-secureboot` built from `talos_image_id` + `talos_version`); non-secureboot roots (e.g. libvirt) must override | `""` |
| `cp_allow_scheduling` | module | Per control plane node: allow workloads on that node (from `nodes_cp[].allow_scheduling`). Applied per node via the Talos `cluster.allowSchedulingOnControlPlanes` machine-config patch (Sidero docs) | — |

> **Note**: Proxmox doesn't expose `cluster_name`, `kubernetes_version`, `longhorn_enabled`, or `extra_config_patches` — the `talos-cluster` module uses its defaults. Libvirt passes all of them explicitly.

## ⚠️ Changes that destroy your cluster

Some `terraform.tfvars` values make Terraform **destroy and recreate the VMs** instead of updating them in place. A recreated control plane node loses its etcd data; if more than one node is replaced, the cluster loses quorum and the L2 VIP goes down — the cluster comes back empty, and the platform layer (`longhorn`, `argocd`) must be re-applied.

> **Rule of thumb**: `terraform apply` provisions and updates *configuration* and now also drives **rolling Talos upgrades** via `talos_machine.image` (see [Upgrading Talos](#upgrading-talos) below). Only bootstrap image changes and destructive `tfvars` keys still force VM recreation.

### 🔴 Destroys the cluster (VM destroy + recreate)

| tfvars key | What happens |
|------------|--------------|
| `datastore_iso`, `nodes_cp[].datastore` / `nodes_worker[].datastore` | Disks recreated on the new datastore |
| `node_name`, `nodes_cp[].proxmox_node` | Proxmox doesn't migrate VMs between nodes — destroy + create |
| `nodes_cp[].disk_size` / `nodes_worker[].disk_size` (decrease) | Disks can't shrink — destroy + create |
| Removing a node from `nodes_cp` / `nodes_worker` | That VM is destroyed |
| `env_name` | Different resource namespace → full recreate |

### 🟡 Outage without data loss (rolling upgrade / reboot)

| tfvars key | What happens |
|------------|--------------|
| `talos_version` | Bumping the version triggers a **sequential rolling upgrade** via `talos_machine.image` (pull → install → reboot, one node at a time with `-parallelism=1` to protect etcd quorum). No VM recreation, no etcd wipe. `drain_on_upgrade = false`. A fresh `terraform destroy` + `apply` or manually tainting `proxmox_download_file.talos_image` still pulls a new bootstrap image |
| `schematic-{env}.yaml` (editing system extensions) | New schematic ID changes `local.installer_image` → same rolling upgrade path as `talos_version`. The bootstrap disk (`proxmox_download_file.talos_image`) ignores `url` changes (`lifecycle { ignore_changes = [url] }`), so etcd is preserved |
| `network_bridge`, `sdn_zone`, `network_cidr`, `network_mtu`, `network_snat` | SDN config re-pushed, VMs reboot |
| `gateway`, `cluster_vip` | Machine config re-pushed; cluster endpoint changes |
| `kubernetes_version` | Machine config re-pushed (rolling kubelet update) |

> **Note**: `proxmox_download_file.talos_image` now uses a shared `file_name` (`talos-nocloud-amd64-secureboot.img`, no `env`/`version` suffix) and `lifecycle { ignore_changes = [url] }` — bumping `talos_version` or editing the schematic no longer recreates the download file/disks. Upgrades are handled by `talos_machine.image`. `justfile`'s `tf-apply` runs with `-parallelism=1` so those rolling reboots are sequential (bootstrap from scratch is slower — ~15 min × 3 — but etcd-safe; remove the flag if you prefer fast parallel bootstrap).

### 🟢 Safe to change

`endpoint`, `api_token`, `ssh_username`, `ssh_node_address`, `insecure`, `tailscale_auth_key`, `tailscale_domain`, `nodes_cp[].allow_scheduling`.

### Upgrading Talos

Bumping `talos_version` and running `just tf-apply` performs a sequential in-place upgrade via `talos_machine.image` (control planes first, then workers) with `-parallelism=1` to protect etcd quorum. The installer image is platform-aware: `factory.talos.dev/nocloud-installer-secureboot/...` by default (Proxmox/secureboot), overridden to `factory.talos.dev/nocloud-installer/...` for libvirt via `var.installer_image`. `drain_on_upgrade = false` (revisit when dedicated workers carry workloads). Bump the pin in `proxmox/variables.tf` (default `1.13.9`), `libvirt/variables.tf` (`1.13.8`) or `proxmox/environments/<env>/terraform.tfvars`, then apply.

## Outputs

| Output | Providers | Description |
|--------|-----------|-------------|
| `talosconfig` | both | Talos client configuration for talosctl |
| `kubeconfig` | both | Standard kubeconfig for kubectl |
| `kubeconfig_tailscale` | both | Kubeconfig with one context per Tailscale hostname |
| `machine_configuration_cp` | module | Talos machine config for control plane nodes (used by libvirt cloud-init) |
| `machine_configuration_worker` | module | Talos machine config for worker nodes (used by libvirt cloud-init) |

## Access

Use `provider` and `env` to select the cluster (defaults: `proxmox` / `prod`).

### Proxmox

```bash
# LAN (L2 VIP, check your environment's cluster_vip)
talosctl --talosconfig secrets/proxmox/prod/talosconfig.yaml version

# Tailscale (per-node contexts, prod only)
kubectl --kubeconfig secrets/proxmox/prod/kubeconfig.yaml get nodes
kubectl --kubeconfig secrets/proxmox/prod/kubeconfig.yaml config use-context talos-cp1
```

### Libvirt

```bash
# LAN (L2 VIP)
talosctl --talosconfig secrets/libvirt/dev/talosconfig.yaml version

# Tailscale (per-node contexts)
kubectl --kubeconfig secrets/libvirt/dev/kubeconfig.yaml get nodes
kubectl --kubeconfig secrets/libvirt/dev/kubeconfig.yaml config use-context talos-cp1
```

## Why

Hands-on infrastructure-as-code with real hardware. Two providers let you choose your hypervisor — Proxmox VE for production-class clusters or libvirt for lightweight local development — while sharing the same modular, reproducible Talos cluster module.

## Available `just` tasks

All tasks run from the repo root. `provider` (`proxmox` | `libvirt`) and `env` (`prod` | `dev`) select the environment (defaults: `proxmox`/`prod`):

```bash
just tf-apply                              # proxmox/prod (default)
just provider=proxmox env=dev tf-apply     # proxmox/dev
just provider=libvirt env=dev tf-apply     # libvirt/dev
just provider=libvirt env=prod tf-apply    # libvirt/prod
```

| Task | Description |
|------|-------------|
| `tf-fmt` | Format all Terraform files recursively |
| `tf-init` | Initialize Terraform with local backend for the active provider/env |
| `tf-plan` | Plan changes for the active provider/env |
| `tf-apply` | Apply changes (bootstrap or update) — runs with `-parallelism=1` to serialize `talos_machine` reboots and protect etcd quorum (slower cold bootstrap, ~15 min × 3) |
| `tf-destroy` | Tear down the active provider/env (cleans up Tailscale devices first) |
| `gen-secrets` | Extract talosconfig + kubeconfig from state |
| `setup-cli` | `gen-secrets` + merge into `~/.talos/config` and `~/.kube/config` |
| `status` | Show Talos version, extensions, and cluster members |
| `get-schematic-id name="prod"` | Compute schematic ID from `schematic-{name}.yaml` via the Image Factory API |
| `cluster-schematic-id` | Read the active schematic ID from the running cluster |

### Platform (ArgoCD) — now composed

Platform (ArgoCD) is a composable module (`modules/platform`) called from each environment root. One `terraform apply` deploys both infra and platform in one state file at `environments/<provider>/<env>/terraform.tfstate` (kubeconfig at `secrets/<provider>/<env>/kubeconfig.yaml`). The standalone `platform/` root is deprecated — see `platform/DEPRECATED.md` for `terraform state mv` migration.

`tf-platform-*` tasks are kept for backward compatibility and now delegate to `tf-apply`/`tf-plan`/`tf-init` with a deprecation warning:

| Task | Description |
|------|-------------|
| `tf-platform-init` | Deprecated → delegates to `tf-init` |
| `tf-platform-plan` | Deprecated → delegates to `tf-plan` |
| `tf-platform-apply` | Deprecated → delegates to `tf-apply` |
| `tf-platform-destroy` | Deprecated → prints destroy guidance (`tf-destroy` or `terraform destroy -target=module.platform.helm_release.argocd`) |

## Platform (ArgoCD)

The **platform layer** is now a composable module (`modules/platform`) called from each environment root (`environments/<provider>/<env>`). It installs the **platform** on top of the cluster in the same state file and same `terraform apply`:

- **ArgoCD** (`argocd`) — GitOps engine (via `helm_release.argocd` in `modules/platform`).

Longhorn is no longer installed here: it is a platform app of the GitOps repo (`secured-gitops-tailscale-homelab`, `platform/longhorn`, wave 0, gated by a CSI readiness Job). The Longhorn node prerequisites still live in this repo at cluster level: kubelet extraMounts for `/var/lib/longhorn` and the `iscsi-tools` / `util-linux-tools` system extensions.

### Setup flow (composed)

1. `just provider=proxmox env=prod tf-apply` — provisions the cluster (VMs, Talos bootstrap) and then the platform (ArgoCD). The infra health gate (`talos_cluster_health`) blocks until kube-apiserver, etcd, and all nodes are Ready; `module.platform.terraform_data.wait_nodes` then waits for `Ready` nodes before the Helm release.
2. `just provider=proxmox env=prod setup-cli` — regenerates `secrets/proxmox/prod/kubeconfig.yaml` and merges it into the local CLI configs (still useful for out-of-band debugging).
3. GitOps repo bootstrap — ArgoCD syncs the applications from the GitOps repository; Longhorn is deployed as a wave-0 app (with CSI readiness gate) during this step.

Each environment configures the `helm` provider against `secrets/<provider>/<env>/kubeconfig.yaml` (see `environments/<provider>/<env>/provider.tf`). The module accepts `kubeconfig_path = abspath("${path.root}/../../../secrets/<provider>/<env>/kubeconfig.yaml")` and re-triggers the node gate when the kubeconfig hash changes.

**Destroy:** a single `just provider=proxmox env=prod tf-destroy` tears down both infra and platform (one state). To remove only the platform release: `terraform -chdir=environments/proxmox/prod destroy -target=module.platform.helm_release.argocd`.

### Migrating an existing cluster

If the cluster already has ArgoCD installed (for example, via the `init-infra.sh` script from the GitOps repo), you can adopt the existing release into the Terraform state with `terraform import`:

```bash
terraform -chdir=environments/proxmox/prod import 'module.platform.helm_release.argocd' argocd/argocd
```

For legacy `platform/` states, see `platform/DEPRECATED.md` for `terraform state mv` from the standalone root into the composed environment state.

#### Migrating Longhorn to the GitOps repo (legacy)

Longhorn is no longer managed here. If you still have a legacy `platform/` state that contains `helm_release.longhorn`:

```bash
# 1) In the secured repo: push the changes (platform/longhorn + gitops/values) and
#    wait until the longhorn ArgoCD app is Healthy (CSI gate Job completed).
# 2) Only then, in the legacy root, remove the resources from the TF state so the next
#    apply does NOT destroy them:
terraform -chdir=platform state rm helm_release.longhorn kubernetes_namespace_v1.longhorn_system kubernetes_manifest.longhorn_prod_storageclass terraform_data.csi_waiter
# 3) Apply the reduced platform layer (ArgoCD only) in the composed model:
just provider=proxmox env=prod tf-apply
# Do NOT run terraform destroy on helm_release.longhorn: it would delete the volumes.
```

### State

Platform is now composed in each environment root — single state at `environments/<provider>/<env>/terraform.tfstate` (covers both infra `module.proxmox`/`module.libvirt` and `module.platform`). CI restores/backs up a single artifact `tfstate-<provider>-<env>`.

> **Migration note:** legacy locations `platform/terraform.tfstate`, `platform/environments/prod/platform-terraform.tfstate`, `platform/environments/<env>/platform-terraform.tfstate`, and `platform/environments/<provider>/<env>/terraform.tfstate` are superseded by the composed model. Keep old files on disk for manual `terraform state mv` into `environments/<provider>/<env>/module.platform.*` (see `platform/DEPRECATED.md`), but new `just tf-apply` and CI use the single environment state.

## CI/CD

This repo includes a GitHub Actions workflow (`.github/workflows/deploy.yaml`) for automated deployment.

To use it from a fork:

1. Configure your Proxmox endpoint and credentials in your environment's `terraform.tfvars`
2. Create ACL
```bash
	"tagOwners": {
        ...
		"tag:terraform":        ["autogroup:admin"],
		"tag:pve":              ["autogroup:admin"],
	},
    "acls": [
        // Terraform need access to 8006
		{"action": "accept", "src": ["tag:terraform"], "dst": ["tag:pve:*"]},
	],
    "ssh": [
		// Terraform need access using ssh, use ssh from tailscale (https://tailscale.com/kb/1193/tailscale-ssh/)
		{
			"action": "accept",
			"src":    ["tag:terraform"],
			"dst":    ["tag:pve"],
			"users":  ["root"],
		},
	],
```
3. Create a **Tailscale OAuth client** in the admin console with `tag:terraform` ( Add OAuth client → scopes: devices:core:write + auth_keys:write → tags: tag:terraform → copy Client ID + Secret)
4. Add these **GitHub secrets**:

| Secret | Value |
|--------|-------|
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client ID |
| `TS_OAUTH_SECRET` | Tailscale OAuth client secret |
| `PROXMOX_API_TOKEN` | Proxmox API token |
| `TAILSCALE_AUTH_KEY` | Tailscale auth key — **reusable** (see below) |

5. Push to `main` — the workflow validates, applies, and uploads `talosconfig` + `kubeconfig` as artifacts

> **About `TAILSCALE_AUTH_KEY`**: Create it in the Tailscale admin console under **Settings → Keys → Auth keys**. Enable **Reusable** (same key across workflow runs). On `terraform destroy`, the `scripts/destroy-tailscale-devices.sh` script cleans up devices via the Tailscale API before tearing down VMs — no manual cleanup needed.

---

## Related Projects

| Repo | Role |
|------|------|
| [`infra-talos-homelab`](https://github.com/Seom88/infra-talos-homelab) *(this repo)* | Cluster provisioning — Terraform + Talos, machine config patches, system extensions |
| [`secured-gitops-tailscale-homelab`](https://github.com/Seom88/secured-gitops-tailscale-homelab) | GitOps layer — ArgoCD, Vault, Tailscale, storage, platform apps |
