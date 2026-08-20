# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.1.0] - Unreleased
### Added
- **Rolling Talos upgrade** (`scripts/talos-upgrade.sh`) — upgrades a running cluster in place, node by node, preserving etcd:
  - Resolves the latest stable Talos release from GitHub, computes the schematic ID via the Image Factory API, and runs `talosctl upgrade` per node (control planes first, then workers) with a cluster health check after each node
  - Syncs the `talos_version` pin in both `proxmox/variables.tf` and `libvirt/variables.tf` afterwards
- **Justfile upgrade task** — `upgrade` under a new "Talos Upgrade" section: provider-agnostic via `--root {{ provider }}` (proxmox honors `tf_env`; libvirt has no environment)
- **Platform layer in CI** — `.github/workflows/deploy.yaml` now deploys the `platform/` workspace (ArgoCD) after the cluster:
  - `validate` job: platform format check + init/validate
  - `deploy` job: `azure/setup-kubectl` + `azure/setup-helm` actions, platform secrets from cluster outputs, platform state restore/backup as artifact (mirrors the proxmox flow), and `terraform apply -var=env_name`
- **README risk section** — "⚠️ Changes that destroy your cluster": traffic-light tables mapping `terraform.tfvars` changes to VM-destroy (cluster wipe), outage-only, or no-effect, plus the bootstrap-only upgrade guidance
- **Platform root** (`platform/`) — new Terraform workspace that installs **ArgoCD** (v9.5.13) from outside this repo's cluster roots:
  - `platform/main.tf` — declarative pipeline: wait for all nodes Ready → ArgoCD Helm chart
  - `platform/providers.tf` — `helm` provider configured against `secrets/<env>/kubeconfig.yaml`
  - `platform/variables.tf` — `env_name` (default `prod`), `argocd_version` (default `9.5.13`); pinned exact, overridable per environment
  - `platform/values/argocd/` — ArgoCD values moved verbatim from the GitOps repo (`secured-gitops-tailscale-homelab`)
- **Cluster health gate** — `data "talos_cluster_health"` in `proxmox/main.tf`: `terraform apply` blocks until kube-apiserver, etcd and all nodes are Ready (protects both local and CI applies)
- **SDN networking (Proxmox)** — `proxmox/network.tf` now creates the cluster network via Proxmox SDN: simple zone + VNet (the `talosvn` bridge, id matches `network_bridge`, max 8 chars) + subnet (`snat = true`, so VMs reach the internet through the node via MASQUERADE) + `proxmox_sdn_applier` (performs the SDN Apply — without it the bridge does not exist on the node and VM creation fails). VMs depend on the applier so the network exists before they boot
- **Justfile platform tasks** — `tf-platform-init`, `tf-platform-plan`, `tf-platform-apply`, `tf-platform-destroy` (agnostic of provider/env)

### Changed
- **Breaking: `allow_scheduling_on_control_planes` removed** — replaced by a required per-node `allow_scheduling` flag on `nodes_cp` entries. The `talos-cluster` module now takes `cp_allow_scheduling` (index-aligned with `cp_hostnames` / `cp_ips`) and patches each control plane's Talos machine config with `cluster.allowSchedulingOnControlPlanes: true` (per Sidero docs), so the kubelet never registers the `node-role.kubernetes.io/control-plane` taint — durable across node reboots, no `kubectl` requirement
- **Breaking: per-node disk/datastore are now required** — `nodes_cp` / `nodes_worker` require per-node `disk_size` (GB) and `datastore` (Proxmox) / `pool` (libvirt); the global `disk_size_cp`, `disk_size_worker` and `datastore_vm` variables were removed, so there are no fallback defaults
- `talos_version` is now a **bootstrap-only pin** in both `proxmox/variables.tf` and `libvirt/variables.tf` (explicit comment): `terraform apply` no longer doubles as the Talos upgrade path — upgrades run through `just upgrade` (provider-agnostic, see the `provider=` / `tf_env=` unification below)
- Talos Linux default `1.13.6` → `1.13.8` (both roots)
- `README.md` — corrected stale version defaults (`talos_version` 1.13.3 → 1.13.8, `kubernetes_version` 1.36.1 → 1.36.2)
- `README.md` — new "Plataforma (ArgoCD)" section: setup flow (`tf-apply` → `tf-platform-apply` → GitOps bootstrap), plus the Longhorn migration runbook (`terraform state rm` before applying the reduced layer, never `terraform destroy`)
- `README.md` — documented the SDN network reachability requirement: the `talosvn` VNet is isolated (outbound SNAT only), so the machine running `terraform apply` must reach `10.10.0.0/24`; for `prod` the subnet is exposed via a Tailscale subnet router (`tailscale set --advertise-routes=10.10.0.0/24` on the Proxmox host, approve in admin console, `--accept-routes` on Linux clients)
- `proxmox/environments/{dev,prod}/terraform.tfvars` — network bridge renamed `vnet1` → `talosvn`; new `sdn_zone` / `network_cidr` variables; `cluster_vip` corrected to `10.10.0.171` (was outside the `10.10.0.0/24` subnet)
- `proxmox/main.tf` — VM IP prefix/mask now derived from `network_cidr` instead of a hardcoded `/24`
- `proxmox/variables.tf` — added `sdn_zone`, `network_cidr`, `network_mtu`, `network_snat` variables; `network_bridge` doc updated for SDN usage
- **Platform root reduced to ArgoCD only** — the `platform/` Terraform workspace no longer installs Longhorn (`kubernetes_namespace_v1.longhorn_system`, `helm_release.longhorn`, `terraform_data.csi_waiter` and `kubernetes_manifest.longhorn_prod_storageclass` removed; `kubernetes` provider and `longhorn_version` variable dropped)
- **Longhorn moved to the GitOps repo** — deployed by `secured-gitops-tailscale-homelab` as a wave-0 ArgoCD app (`platform/longhorn`) with a CSI readiness gate (Job `longhorn-csi-wait`)
- **Runbook for migration** — README documents `terraform state rm` for the old Longhorn resources before applying the reduced layer, so volumes are never destroyed (never `terraform destroy` `helm_release.longhorn`)
- **Justfile unified around `provider=` / `tf_env=`** — one task set now serves both providers; the dedicated libvirt tasks (`tf-libvirt-*`, `gen-libvirt-secrets`, `setup-libvirt-cli`, `upgrade-libvirt`) were removed. Backend/var-file arguments, secrets path, and status labels are derived from the active provider/env; platform tasks no longer chain `gen-secrets` or pass backend/`env_name` flags
- `justfile` — comments and task descriptions fully translated to English
- `README.md` — task tables and quick-start examples updated to the unified `just` task set; platform setup flow and state notes updated; Longhorn migration runbook translated to English

## [1.0.2] - 2026-07-16

### Added
- **Tailscale device cleanup script** (`scripts/destroy-tailscale-devices.sh`) — deletes Tailscale devices via API before `terraform destroy`, preventing stale "dead" nodes from piling up in the tailnet
- `scripts/` directory added to repo structure

### Changed
- `justfile` — `tf-destroy` and `tf-libvirt-destroy` now call the cleanup script before Terraform destroy (skips gracefully if OAuth env vars aren't set)
- `.github/workflows/destroy.yaml` — added "Clean up Tailscale devices" step before terraform destroy
- `README.md` — removed ephemeral key references, documented cleanup script, updated CI/CD secrets table

## [1.0.1] - 2026-07-16

### Added
- **Destroy workflow** — GitHub Actions `destroy.yaml` with confirmation gate and state restoration
- Demo screenshot (`docs/demo.png`)

### Changed
- Talos provider `0.11` → `0.12.0-alpha.5` (temporary — fixes [inconsistent final plan bug](https://github.com/siderolabs/terraform-provider-talos/issues/352); revert when v0.12.0 is stable)
- Proxmox provider `0.109.0` → `0.111.1`
- Talos Linux `1.13.3` → `1.13.6`
- Kubernetes `1.36.1` → `1.36.2`

### Fixed
- CI badge repo name in README

## [1.0.0] - 2026-07-15

### Features

- **Two providers** — Proxmox VE (`bpg/proxmox`) and libvirt (`dmacvicar/libvirt`) with a shared `talos-cluster` module
- **Modular architecture** — infrastructure (VMs) and configuration (Talos/K8s) separated; `talos-cluster` works with any provider
- **Talos Linux 1.13** on Kubernetes 1.36 with UEFI secure-boot-ready VMs
- **Per-environment state** — dev/prod isolation with separate `.tfvars`, backend state, and secrets
- **Tailscale integration** — MagicDNS mesh networking with per-node kubeconfig contexts (prod only)
- **Longhorn-ready** — kubelet extraMounts for `/var/lib/longhorn` + `iscsi-tools` and `util-linux-tools` extensions
- **Custom Talos images** — Image Factory schematics bundle `iscsi-tools`, `qemu-guest-agent`, `tailscale`, `util-linux-tools`
- **Image caching (libvirt)** — nocloud raw images downloaded once, reused across applies
- **NAT networking (libvirt)** — dedicated `virbr-talos` bridge with DHCP reservations and DNS from node MACs
- **CI/CD** — GitHub Actions workflow with Tailscale mesh, state persistence via artifacts, fmt + validate checks
- **Justfile tasks** — `tf-apply`, `tf-destroy`, `setup-cli`, `status`, `get-schematic-id` and more

### Added
- MIT license
- Badges (Terraform, Talos, License, CI)
- Mermaid architecture diagram
- "How it works" section in README
- CONTRIBUTING.md
- Demo screenshot placeholder (`docs/demo.png`)
- Related projects section with correct links

### Fixed
- Dev environment description in README (was "1 cp + 3 workers", actually 3 cp)
- Disk size defaults documentation (20 GB CP, 100 GB worker)
- `username`/`password` marked as legacy in README
- Terraform formatting across all `.tf` and `.tfvars` files
- Talos provider version pinned to `0.11` in Proxmox
- Related projects table links

### Changed
- `locals` block removed from `proxmox/main.tf`, expression passed directly to module
- CI fmt check runs from repo root (covers `libvirt/` and `modules/`)

## [0.1.0] - 2026-06-01

### Added
- Proxmox provider support (`bpg/proxmox`)
- Libvirt provider support (`dmacvicar/libvirt`)
- Provider-agnostic `talos-cluster` module
- Per-environment state management (dev/prod)
- Tailscale integration with per-node kubeconfig contexts
- Longhorn-ready kubelet extraMounts
- Custom Talos image via Image Factory (iscsi-tools, qemu-guest-agent, tailscale, util-linux-tools)
- Image caching for libvirt provider
- NAT networking with DHCP for libvirt
- GitHub Actions CI/CD workflow
- Justfile with helper tasks
