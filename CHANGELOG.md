# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Native Talos v1.14 swap provisioning for every node: a fixed 4 GiB `SwapVolumeConfig` on the existing installation disk (`/dev/sda` Proxmox, `/dev/vda` libvirt), explicitly avoiding Longhorn data disks.
- Kubernetes pod swap support through `KubeletConfig.config.memorySwap.swapBehavior: LimitedSwap`.
- Shared `ZswapConfig` with `maxPoolPercent: 20` and documented `SysctlConfig` tuning (`vm.swappiness: "130"`, `vm.page-cluster: "0"`) for control-plane and worker nodes.
- Swap and zswap are configured together so zswap can act as a compressed RAM-backed cache in front of the swap device.

### Changed
- Proxmox and libvirt now apply the swap configuration through their existing machine-configuration paths without changing VM disk layouts or Longhorn `UserVolumeConfig` selectors.

### Security
- LUKS2 encryption is intentionally not enabled for swap in this change; the swap partition remains on the system disk.

## [2.2.0] - 2026-09-23

### Added
- `install_disk_match` variable — configurable `provisioning.diskSelector.match` CEL on `disk.dev_path` (`/dev/vda` libvirt, `/dev/sda` Proxmox); required after the SCSI migration.
- Cilium values layering — prod lean base (`values.yaml`) + dev full-observability overlay (`values-dev.yaml`) via `cilium_values_file`.
- Per-disk `ssd` flag on Proxmox `nodes_cp/nodes_worker` (default `true`).
- ADR 006 (VAAPI/QuickSync sharing rejected on 8700T; CPU-only Immich).

### Changed
- **Breaking: Proxmox boot/data disks `virtio` → SCSI (`scsi0/scsiN`, `virtio-scsi-single`, `ssd=true`).** Existing VMs recreate; pair with `install_disk_match = "/dev/sda"`.
- **Breaking: `talos-cluster` variables now required** (`cluster_name`, `kubernetes_version`, `longhorn_enabled`, `extra_config_patches`, `drain_on_upgrade`, `install_disk_match`) — callers must pass them explicitly.
- **Breaking-ish: Kubernetes `1.36.3` → `1.37.0`.** Rollout with `-parallelism=1`, verify bootstrap in libvirt/dev first.
- Talos `1.14.0` → `1.14.1`; Cilium `1.20.1` → `1.20.2`; ArgoCD `10.7.0` → `10.9.2`; `bpg/proxmox` `0.113.1` → `0.114.0`.
- Cilium operator `1` → `2` replicas (HA) + ArgoCD controller `1` → `2`; memory ballooning disabled (`floating = 0`); Proxmox `proxmox/dev` now wires `cluster_name`/`kubernetes_version`/`longhorn_enabled`/`extra_config_patches` like prod.
- Proxmox network device pins `model = "virtio"` to avoid default drift.

### Fixed
- `platform` `terraform fmt` drift.

## [2.1.0] - 2026-09-14

### Added
- Canonical Image Factory module — extensions → schematic → URLs from data sources, no YAML files; `schematic_id` output replaces the factory API POST.
- Cilium kube-proxy-free + Gateway API via Helm, with operator HA knob, socketLB fix for `kubectl port-forward/exec/logs`, Prometheus/Hubble/Grafana observability, and resource requests sized for the 32 GiB single host.
- Deterministic App-of-Apps sync-wave ordering (Synced + Healthy gate, opt-out per app).
- Renovate coverage for Cilium, Gateway API CRDs and Kubernetes; safe automerge for minor/patch bumps.
- ADR 004 (single control-plane topology for the 32 GiB homelab) and docs split into topic guides.
- Metrics Server via kubelet certificate rotation (Option 2): `KubeletConfig rotate-server-certificates` on all nodes + `kubelet-serving-cert-approver` and `metrics-server` external manifests on controlplanes.
- Proxmox CPU shares + affinity: `cpu_units` (200 control-plane / 100 workers) and `cpu_affinity` pool `2-5,8-11` per Talos node in prod `tfvars` (cores 0-1 reserved for host/TrueNAS); `just affinity-sync` applies them as root via `qm set` (VMIDs resolved by hostname, `qm config` proof), drift contract in `docs/operations.md` (`tfvars` wins), and `lifecycle { ignore_changes = [cpu[0].affinity] }` so API-token CI never fights the `root@pam`-only value.

### Changed
- **Breaking: Talos 1.13.9 → 1.14.0 (K8s stays 1.36.3).** Machine-config patches moved to the 1.14 multi-doc format (scheduling, install, Cilium); kubelet `extraMounts` removed — Longhorn storage now comes from UserVolumeConfigs via `defaultDataPath` (see ADR 005). Rollout: verify a fresh bootstrap in libvirt/dev first, then apply with `-parallelism=1`.
- **Breaking: schematic YAML deleted.** Installer and disk URLs now come from Image Factory data sources (secureboot flavor on Proxmox, plain on libvirt without secureboot).
- **Breaking: one UserVolumeConfig per `disks[].name`** (was a single generic `data` volume); legacy `data_disk_size` variables removed — data disks are declared only via `disks[]`.
- **Breaking: prod topology is now 1 control-plane + 3 workers** per ADR 004 (was 3 control-planes).
- Talos provider `0.12.0-alpha.5` → `0.12.0-beta.0`; Kubernetes version now wired explicitly (fixes a bogus `1.37.0-rc.1` default); ArgoCD `9.5.13` → `10.7.0`; Cilium `1.18.0` → `1.20.1` with Gateway API `v1.6.1` CRDs.
- Libvirt disks are thin `qcow2` with host-side conversion; the Terraform health gate is Talos-layer only (node-Ready waits moved to the platform layer); platform Helm releases gained values layering + timeout hardening; all live docs synced to the 1.14 reality.

### Fixed
- SDN SNAT rules lost after Proxmox reboot (self-healing boot service).
- Longhorn data-path drift + single-disk control-plane blocking 3-replica scheduling; storage-class disk selector cleared for virtio.
- Libvirt UEFI boot failure after the `qcow2` migration (driver type declared).
- ArgoCD `/argocd` path stripping at the gateway; Cilium ServiceMonitors disabled until monitoring is synced.
- `just affinity-sync` SSH stdin bug: the first `ssh` consumed the VM-list stdin so only the first node applied; fixed with `ssh -n` on all three host calls.

## [2.0.0] - 2026-08-28

### Added
- ADR 001 (Tailscale node extension removed, subnet routing kept) + destroy-cleanup history.
- S3-compatible backend for prod state with `.env.example` credentials.
- `enable_health_check` gate so destroy/bootstrap never blocks on the health data source.
- Provider modules (`proxmox`, `libvirt`) + symmetrical `environments/<provider>/<env>/` layout; platform composed into each environment (single state, single apply).
- Platform module (ArgoCD in-cluster); cluster health gate; Proxmox SDN networking; Justfile platform wrappers.
- `installer_image` override + `talos_machine` resources (in-place upgrades, no VM recreation); libvirt storage pool, SecureBoot, deterministic MACs, DHCP reservations (no cloud-init), persistent image cache, bootstrap-only base image.
- Input validations, `drain_on_upgrade` knob, explicit `kubernetes` provider, 4-env CI validate matrix, Renovate bot.

### Removed
- Standalone `platform/` root (now composed into environments; single state each).
- `cluster_vip`, `tailscale_domain`, `kubeconfig_tailscale` outputs, Tailscale node extension (commented, see ADR 001), destroy-cleanup script, CI tfstate artifact handling (S3 only now).

### Fixed
- Proxmox SDN egress pinned (SNAT + firewall) so nodes reach the internet.
- `talos_machine_secrets` bootstrap-only (version bumps no longer rotate the CA); health hang/timeout fixes; kubeconfig write without ephemeral; libvirt `env_name`, trigger maps, `.gitignore`, provider pins and dev lockfiles synced.

### Changed
- **Breaking: platform composed into environments** — one `terraform apply` provisions cluster + ArgoCD; single state per environment.
- **Breaking: control-plane scheduling is now a per-node `allow_scheduling` flag** (was a global switch); **per-node disk/datastore required** (was global fallbacks).
- `talos_version` upgrades are declarative rolling reboots (`-parallelism=1`); Talos `1.13.6` → `1.13.9`.
- Longhorn moved to the GitOps repo (wave-0 app with CSI gate) + migration runbook.
- Justfile unified around `provider=`/`tf_env=`; `tf-apply` split into fast bootstrap vs sequential upgrades; image downloads bootstrap-only.
- CI simplified around S3 state (deploy + destroy rewrites, no artifact juggling).
- Libvirt root modularized (network/image/vms/cluster/pool); cloud-init and shell-polling waits removed.
- `talos_machine_bootstrap` → `talos_cluster` resource; `required_version >= 1.11`; provider bumps; SDN variables; endpoint/TLS/domain cleanups; prod topology fixtures for HA testing.
- Docs restructured for the composed model (structure, platform, setup, state, tasks) + SDN reachability requirement; Justfile translated to English.

## [1.0.2] - 2026-07-16

### Added
- Tailscale device cleanup on destroy.

### Changed
- Destroy tasks and workflow call the cleanup script; README updated.

## [1.0.1] - 2026-07-16

### Added
- Destroy workflow with confirmation gate; demo screenshot.

### Changed
- Talos provider `0.11` → `0.12.0-alpha.5` (temporary, upstream bug #352); Proxmox provider, Talos `1.13.6` and Kubernetes `1.36.2` bumps.

### Fixed
- CI badge repo name.

## [1.0.0] - 2026-07-15

### Added
- First stable release: Proxmox + libvirt providers sharing `talos-cluster`; Talos 1.13 on K8s 1.36; per-env state; Tailscale mesh; Longhorn-ready nodes; Image Factory images; libvirt NAT/DHCP + image cache; CI/CD; Justfile; MIT license; README/CONTRIBUTING/docs and diagrams.

## [0.1.0] - 2026-06-01

### Added
- Initial scaffold: both providers, `talos-cluster` module, per-env state, Tailscale, Longhorn-ready nodes, factory images, libvirt cache + NAT, CI workflow, Justfile.
