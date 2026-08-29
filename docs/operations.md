# Operations

> What destroys the cluster, what causes a rolling reboot, what's safe — and how to upgrade Talos in place.

[← Back to README](../README.md) · [Variables →](./variables.md) · [Platform →](./platform.md)

Some `terraform.tfvars` values make Terraform **destroy and recreate the VMs** instead of updating them in place. A recreated control plane node loses its etcd data; if more than one node is replaced, the cluster loses quorum — the cluster comes back empty, and the platform layer is re-provisioned on the next single `terraform apply` (ArgoCD via `module.platform`, Longhorn via the GitOps repo wave-0 app).

> **Rule of thumb**: `terraform apply` provisions and updates *configuration* and now also drives **rolling Talos upgrades** via `talos_machine.image` (see [Upgrading Talos](#upgrading-talos) below). Only bootstrap image changes and destructive `tfvars` keys still force VM recreation.

## 🔴 Destroys the cluster (VM destroy + recreate)

| tfvars key | What happens |
|------------|--------------|
| `datastore_iso`, `nodes_cp[].datastore` / `nodes_worker[].datastore` | Disks recreated on the new datastore |
| `node_name`, `nodes_cp[].proxmox_node` | Proxmox doesn't migrate VMs between nodes — destroy + create |
| `nodes_cp[].disk_size` / `nodes_worker[].disk_size` (decrease) | Disks can't shrink — destroy + create |
| Removing a node from `nodes_cp` / `nodes_worker` | That VM is destroyed |
| `env_name` | Different resource namespace → full recreate |

## 🟡 Outage without data loss (rolling upgrade / reboot)

| tfvars key | What happens |
|------------|--------------|
| `talos_version` | Bumping the version triggers a **sequential rolling upgrade** via `talos_machine.image` (pull → install → reboot, one node at a time with `-parallelism=1` to protect etcd quorum). No VM recreation, no etcd wipe. `drain_on_upgrade = false`. A fresh `terraform destroy` + `apply` or manually tainting `proxmox_download_file.talos_image` still pulls a new bootstrap image |
| `schematic-{env}.yaml` (editing system extensions) | New schematic ID changes `local.installer_image` → same rolling upgrade path as `talos_version`. The bootstrap disk (`proxmox_download_file.talos_image`) ignores `url` changes (`lifecycle { ignore_changes = [url] }`), so etcd is preserved |
| `network_bridge`, `sdn_zone`, `network_cidr`, `network_mtu`, `network_snat` | SDN config re-pushed, VMs reboot |
| `gateway` | Machine config re-pushed; cluster endpoint (direct per-node IPs) changes |
| `kubernetes_version` | Machine config re-pushed (rolling kubelet update) |

> **Note**: `proxmox_download_file.talos_image` now uses a shared `file_name` (`talos-nocloud-amd64-secureboot.img`, no `env`/`version` suffix) and `lifecycle { ignore_changes = [url] }` — bumping `talos_version` or editing the schematic no longer recreates the download file/disks. Upgrades are handled by `talos_machine.image`. `justfile`'s `tf-apply` runs with `-parallelism=10` for fast bootstrap; use `tf-apply-upgrade` (`-parallelism=1`) for sequential Talos rolling upgrades.

## 🟢 Safe to change

`endpoint`, `api_token`, `ssh_username`, `ssh_node_address`, `insecure`, `nodes_cp[].allow_scheduling`.

> Tailscale node extension is disabled ([ADR 001](./adr/001-remove-tailscale-extension.md)) — uncomment variables in `variables.tf` / `schematic-*.yaml` at repo root to re-enable.

## Upgrading Talos

Bumping `talos_version` and running `just tf-apply-upgrade` (or `just tf-apply -parallelism=1`) performs a sequential in-place upgrade via `talos_machine.image` (control planes first, then workers) with `-parallelism=1` to protect etcd quorum. The installer image is platform-aware: `factory.talos.dev/nocloud-installer-secureboot/...` by default (Proxmox/secureboot), overridden to `factory.talos.dev/nocloud-installer/...` for libvirt via `var.installer_image`. `drain_on_upgrade = false` (revisit when dedicated workers carry workloads). Bump the pin in `modules/proxmox/variables.tf` (default `1.13.9`), `modules/libvirt/variables.tf` (`1.13.9`) or `environments/<provider>/<env>/terraform.tfvars`, then apply.

```bash
# Example: bump talos_version in terraform.tfvars (or variables.tf default), then:
just provider=proxmox env=prod tf-apply-upgrade
# or
just provider=libvirt env=dev tf-apply-upgrade
```

**Details:**

- `talos_machine.control_plane` / `talos_machine.worker` set `image = local.installer_image` (`factory.talos.dev/nocloud-installer-secureboot/<schematic-id>:v<version>` by default).
- `drain_on_upgrade` is parameterized (`bool`, default `false`, platform-aware — `false` for prod with Longhorn, opt-in `true` for dev).
- `time_sleep.post_bootstrap` is `10s`; `talos_cluster_health` has `read = "10m"` and blocks until kube-apiserver, etcd, and all nodes are Ready.
- Cold bootstrap (`terraform destroy` + `apply`) uses `-parallelism=10` (fast ~8 min); upgrades use `-parallelism=1` (safe quorum).

## Notes

- **Validation:** 57 blocks cover semver, CIDR, IP, `^(dev|prod)$` — invalid `tfvars` fail at `terraform validate` before any VM mutation. See [Variables](./variables.md) and [CI/CD](./ci-cd.md).
- **State:** Single state file at `environments/<provider>/<env>/terraform.tfstate` (infra + platform). Prod is S3 (RustFS `terraform-homelab`), dev is local. See [Platform](./platform.md#state).
- **Networking reboot drift:** After PVE reboot, `pve-sdn-ensure.service` heals the SDN bridge + MASQUERADE automatically. See [Networking](./networking.md) and [ADR 003](./adr/003-sdn-snat-runtime-drift.md).

---

Next: [Platform →](./platform.md) · [Usage →](./usage.md) · [Networking →](./networking.md)
