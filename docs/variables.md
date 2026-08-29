# Variables

> All input variables for Proxmox, Libvirt, and the shared `talos-cluster` module — verbatim from the original README, cleaned and cross-linked.

[← Back to README](../README.md) · [Architecture →](./architecture.md) · [Networking →](./networking.md)

All 4 envs ship input validations — 57 blocks total — semver for `talos_version`/`kubernetes_version`/`argocd_version`, CIDR for `network_cidr`, IP for `gateway`/`cp_ips`, non-empty `cluster_name`/`env_name` + `^(dev|prod)$`, nullable guards for `machine_secrets`/`client_configuration`. See [Validation & Quality](../README.md#validation--quality) and [CI/CD](./ci-cd.md).

## Proxmox

| Variable | Description | Default |
|----------|-------------|---------|
| `env_name` | Environment name (`dev` / `prod`); selects schematic file — validated `^(dev\|prod)$` | — |
| `endpoint` | Proxmox API URL (e.g. `https://10.10.10.1:8006`) | — |
| `api_token` | Proxmox API token in format `user@realm!tokenid=secret` | — |
| `username` | Proxmox API user — legacy, commented out in code | — |
| `password` | Proxmox API password — legacy, commented out in code | — |
| `ssh_username` | SSH user for Proxmox node operations | `root` |
| `ssh_node_address` | SSH address for the Proxmox node (e.g. Tailscale hostname) | — |
| `insecure` | Skip TLS verification | `false` |
| `node_name` | Proxmox node for image download | — |
| `gateway` | VM default gateway | — |
| `network_bridge` | Proxmox network bridge (must match SDN VNet id `talosvn` when using SDN) | `vmbr0` |
| `sdn_zone` | SDN zone id for the Talos network | `talos` |
| `network_cidr` | CIDR for the SDN VNet subnet (must contain node IPs) | `10.10.0.0/24` |
| `network_mtu` | MTU for the SDN zone | `1500` |
| `network_snat` | Enable SNAT on the SDN subnet (MASQUERADE for VM egress) | `true` |
| `datastore_iso` | Datastore for ISO/raw images | `local` |
| `nodes_cp` | Control plane nodes (hostname, ip, cores, memory, proxmox_node, disk_size, datastore, allow_scheduling — all required) | — |
| `nodes_worker` | Worker nodes (hostname, ip, cores, memory, proxmox_node, disk_size, datastore — all required) | — |
| `talos_version` | Talos Linux version | `1.13.9` |
| `argocd_version` | ArgoCD Helm chart version | `9.5.13` |
| `enable_health_check` | Enable `talos_cluster_health` gate (set `false` for destroy) | `true` |

> Tailscale node extension is disabled ([ADR 001](./adr/001-remove-tailscale-extension.md)): node extension variables are commented out in `variables.tf` as `Tailscale extension disabled`. Subnet routing only (`10.10.0.0/24`). API uses direct per-node IPs (health-gated, removed in 2.0.0). See [Networking](./networking.md).

## Libvirt

| Variable | Description | Default |
|----------|-------------|---------|
| `nodes_cp` | Control plane nodes (hostname, ip, mac, cores, memory, disk_size, pool, allow_scheduling — all required) | — |
| `nodes_worker` | Worker nodes (hostname, ip, mac, cores, memory, disk_size, pool — all required) | — |
| `pool_name` | Dedicated storage pool name | `talos-pool` |
| `pool_path` | Filesystem path for the pool | `/var/lib/libvirt/images/talos` |
| `gateway` | Default gateway IPv4 | `10.0.1.1` |
| `network_cidr` | Subnet CIDR for the Libvirt NAT network | `10.0.1.0/24` |
| `secureboot` | Enable UEFI SecureBoot (q35) | `true` |
| `talos_image_cache_dir` | Local cache for nocloud raw images | `~/.cache/talos-images` |
| `cluster_name` | Talos / Kubernetes cluster name | `talos-cluster` |
| `talos_version` | Talos Linux version — semver validated | `1.13.9` |
| `kubernetes_version` | Kubernetes version — semver validated | `1.36.2` |
| `longhorn_enabled` | Inject kubelet extraMounts for Longhorn | `true` |
| `extra_config_patches` | Additional Talos machine config patches | `[]` |
| `env_name` | Selects schematic file (`schematic-<env_name>.yaml`) — validated `^(dev\|prod)$` (`dev` in `libvirt/dev`, `prod` in `libvirt/prod` + both proxmox envs) | `dev` |
| `argocd_version` | ArgoCD Helm chart version — semver validated | `9.5.13` |
| `enable_health_check` | Enable `talos_cluster_health` gate (set `false` for destroy) | `true` |

> See above — same Tailscale note as Proxmox above.

## Shared (`modules/talos-cluster`)

| Variable | Providers | Description | Default |
|----------|-----------|-------------|---------|
| `talos_version` | both | Talos Linux version | `1.13.9` |
| `installer_image` | module | Installer container image for `talos_machine.image` (e.g. `factory.talos.dev/nocloud-installer/<schematic-id>:v<version>`). Must match platform flavor — secureboot roots can omit (defaults to `nocloud-installer-secureboot` built from `talos_image_id` + `talos_version`); non-secureboot roots (e.g. libvirt) must override | `""` |
| `cp_allow_scheduling` | module | Per control plane node: allow workloads on that node (from `nodes_cp[].allow_scheduling`). Applied per node via the Talos `cluster.allowSchedulingOnControlPlanes` machine-config patch (Sidero docs) | — |

> **Note**: Proxmox doesn't expose `cluster_name`, `kubernetes_version`, `longhorn_enabled`, or `extra_config_patches` — the `talos-cluster` module uses its defaults. Libvirt passes all of them explicitly. Tailscale node extension and the former shared API address were removed in 2.0.0 (direct per-node IPs via health gate).

## Validation notes

- 57 validation blocks across `modules/talos-cluster`, `modules/proxmox`, `modules/libvirt` and all 4 envs (`environments/proxmox/{dev,prod}`, `environments/libvirt/{dev,prod}`).
- `drain_on_upgrade` — `bool`, default `false`, parameterized and platform-aware (`false` for Longhorn prod, opt-in `true` for dev). Controls whether nodes are drained during `talos_machine` rolling upgrades.
- Provider versions are pinned: `bpg/proxmox 0.111.1`, `dmacvicar/libvirt ~>0.9.8`, `siderolabs/talos 0.12.0-alpha.5` ([ADR 002](./adr/002-pinned-talos-provider-alpha.md)), `helm ~>2.17`, `kubernetes ~>2.38`, `time ~>0.14`.
- `kubernetes_version` is intentionally **not** managed by Renovate — owned by `talos_cluster.kubernetes_version` with `ignore_kubernetes_upgrade_drift = true`. See [CI/CD](./ci-cd.md).

---

Next: [Operations →](./operations.md) · [Usage →](./usage.md) · [Platform →](./platform.md)
