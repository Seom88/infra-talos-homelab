# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.1] - 2026-08-28
### Fixed
- **Proxmox SDN egress declaratively pinned (`modules/proxmox/main.tf`, `environments/proxmox/{prod,dev}/terraform.tfvars`)** — `network_snat = true` now explicit in both tfvars (was implicit default) and `network_device { firewall = false }` on `proxmox_virtual_environment_vm.talos` / `talos_worker`. Prevents Proxmox datacenter firewall from overriding the SDN `MASQUERADE` and causing `discovery.talos.dev:443` `DeadlineExceeded` / `network is unreachable` (IPv6) / `connection reset by peer` warnings seen on `talos-cp1` dashboard (Talos v1.13.9, `SIDEROLINK n/a`, `KUBELET/APISERVER Healthy`). Verified via `talosctl -n 10.10.0.11 debug docker.io/library/alpine:latest` — `ping 1.1.1.1`, `nslookup discovery.talos.dev` (18.226.100.232 + 2600:1f16:790:7900::), `wget --spider https://discovery.talos.dev:443` and `registry.k8s.io` now succeed

## [2.0.0] - 2026-08-27
### Added
- **ADR 001 — Remove Tailscale Talos extension, keep subnet routing (`docs/adr/001-remove-tailscale-extension.md`)** — 322-line MADR documenting why `siderolabs/tailscale` was disabled (Tailscale 1.98.2 CVE pinned to Talos version, ghost devices left in tailnet on `terraform destroy` — prior fix `scripts/destroy-tailscale-devices.sh` in commits `e431723`/`3db09b2`/`a63eeaf`), last active commit `4710f8a`, disabled in `d2aae06`. Decision: keep only subnet routing (`tailscale set --advertise-routes=10.10.0.0/24` on Proxmox host + `tailscale/github-action@v4` in CI for `10.10.0.0/24` reachability). Includes consequences, restore guide (uncomment `tailscale_auth_key` in 7 `variables.tf` + 2 `ExtensionServiceConfig` blocks + 6 passthroughs + `siderolabs/tailscale` in `schematic-*.yaml` + `just get-schematic-id`), and archived README sections
- **S3 backend for prod state (`environments/proxmox/prod`, `environments/libvirt/prod`)** — migrated from `backend "local"` to `backend "s3"` backed by RustFS (`https://rustfs.lonk-mirfak.ts.net`, bucket `terraform-homelab`, path-style, `skip_*` for S3-compatible API). Keys `proxmox/prod/terraform.tfstate` and `libvirt/prod/terraform.tfstate`. Credentials via `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars
- **`.env.example` with S3 credentials** — template for `TF_VAR_api_token`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (RustFS endpoint)
- **`enable_health_check` gate (`modules/proxmox`, `modules/libvirt`, all `environments/*`)** — `variable "enable_health_check" bool default true` + `TF_VAR_enable_health_check=false` in `just tf-destroy` (and for disposable `tf-apply`) so `data "talos_cluster_health"` has `count = 0` on destroy/bootstrap and never blocks `terraform destroy` with `Still reading...` / `Ephemeral value not allowed`. Applies block until K8s Ready with `read = "10m"` (was `5m`)
- **Provider modules (`modules/proxmox`, `modules/libvirt`)** — extracted hypervisor-specific infrastructure logic into reusable Terraform modules, consuming the underlying `modules/talos-cluster` module.
- **Symmetrical Environments (`environments/<provider>/<env>/`)** — unified structure for both Proxmox (`dev`, `prod`) and Libvirt (`dev`, `prod` scaffold). Terraform roots now live directly in their environment directories, auto-loading `terraform.tfvars` and storing state locally without needing `-var-file` or `-backend-config` flags.
- **Platform layer in CI** — `.github/workflows/deploy.yaml` now does single `terraform apply` per environment (infra+platform atomic) in `environments/${TF_ROOT}/${TF_ENV}` (originally with artifact `tfstate-${TF_ROOT}-${TF_ENV}`, now S3-only — see CI S3 simplification below); `validate` job checks `modules/platform` (format + init/validate).
- **README risk section** — "⚠️ Changes that destroy your cluster": traffic-light tables mapping `terraform.tfvars` changes to VM-destroy (cluster wipe), outage-only, or no-effect, plus the bootstrap-only upgrade guidance
- **Platform module (`modules/platform`)** — composable Terraform module that installs ArgoCD (v9.5.13) *inside* each environment root: `main.tf` wait for Ready nodes → ArgoCD Helm chart, `variables.tf` `kubeconfig_path`/`argocd_version`, `values/argocd/` copied from GitOps repo. Helm provider is now configured in each `environments/<provider>/<env>/provider.tf`, not in a separate root.
- **Cluster health gate** — `data "talos_cluster_health"` in `proxmox/main.tf` and `libvirt/cluster.tf`: `terraform apply` blocks until kube-apiserver, etcd and all nodes are Ready (protects both local and CI applies)
- **SDN networking (Proxmox)** — `proxmox/network.tf` now creates the cluster network via Proxmox SDN: simple zone + VNet (the `talosvn` bridge, id matches `network_bridge`, max 8 chars) + subnet (`snat = true`, so VMs reach the internet through the node via MASQUERADE) + `proxmox_sdn_applier` (performs the SDN Apply — without it the bridge does not exist on the node and VM creation fails). VMs depend on the applier so the network exists before they boot
- **Justfile platform tasks** — `tf-platform-init`, `tf-platform-plan`, `tf-platform-apply`, `tf-platform-destroy` are now deprecated wrappers delegating to standard `tf-*` tasks (composed model, no separate state).
- **`installer_image` variable** (`modules/talos-cluster/variables.tf`) — `string`, default `""`; platform-aware override for `talos_machine.image` (e.g. `factory.talos.dev/nocloud-installer/<schematic-id>:v<version>`). Secureboot roots can omit it (defaults to `factory.talos.dev/nocloud-installer-secureboot/<schematic-id>:v<version>` built from `talos_image_id` + `talos_version`)
- **`talos_machine` resources** (`modules/talos-cluster/main.tf`) — replace `talos_machine_configuration_apply` (`control` + `worker`) with `talos_machine.control_plane` / `talos_machine.worker` (`image = local.installer_image`, `drain_on_upgrade = false`). Bumping `talos_version` now triggers an in-place pull → install → reboot without recreating VMs; `talos_machine_bootstrap` now depends on `talos_machine.control_plane`
- **Dedicated Libvirt Storage Pool** (`libvirt/pool.tf`) — creates `talos-pool` (`libvirt_pool`) at `/var/lib/libvirt/images/talos` for persistent image and volume management
- **Libvirt SecureBoot support** (`libvirt/vms.tf`, `libvirt/image.tf`, `libvirt/variables.tf`) — unified SecureBoot workflow with Proxmox: downloads `nocloud-amd64-secureboot.raw.xz` image, configures UEFI OVMF with host edk2 paths (`/usr/share/edk2/ovmf/OVMF_CODE.fd` and `OVMF_VARS.fd`), and binds installer image to `nocloud-installer-secureboot`

### Removed
- **Platform root (`platform/`)** — deleted entirely. State is now single `environments/<provider>/<env>/terraform.tfstate` containing both infra and platform (`module.platform.helm_release.argocd`). Migration: `terraform state mv` or `terraform import 'module.platform.helm_release.argocd' argocd/argocd` from legacy `platform/terraform.tfstate` or `platform/environments/...`.
- **VIP (`cluster_vip`)** — removed from `modules/talos-cluster` and all environment `terraform.tfvars`; the virtual IP caused bootstrap failures and conflicted with node reconfiguration. API server access now relies on direct per-node IPs.
- **Tailscale MagicDNS domain (`tailscale_domain`)** — removed from `modules/talos-cluster/variables.tf`, `modules/proxmox/variables.tf`, `modules/libvirt/variables.tf` and all environment `variables.tf` / `main.tf` (`environments/proxmox/{dev,prod}`, `environments/libvirt/prod`; `environments/libvirt/dev` still has a stale passthrough). `modules/talos-cluster/main.tf` locals `cp_names` / `worker_names` no longer build FQDNs (`"${hostname}.${var.tailscale_domain}"`) — they are now verbatim `var.cp_hostnames` / `var.worker_hostnames`. Tailscale integration now relies solely on `tailscale_auth_key` (opt-in); node addressing uses IPs/short hostnames. Also removed from `modules/proxmox/main.tf` and `modules/libvirt/cluster.tf` module calls
- **`kubeconfig_tailscale` outputs (7 files)** — deleted from `environments/proxmox/{dev,prod}/outputs.tf`, `environments/libvirt/{dev,prod}/outputs.tf`, `modules/proxmox/outputs.tf`, `modules/libvirt/outputs.tf`, `modules/talos-cluster/outputs.tf` (the `yamlencode` per-node `https://${host}:6443` kubeconfig that used short hostnames since the `all_tailscale_names → all_nodes_names` rename); canonical kubeconfig is now the VIP-less `talos_cluster_kubeconfig.kubeconfig_raw` via subnet route (`10.10.0.0/24`). Verified `grep -R kubeconfig_tailscale --include="*.tf"` → 0 hits
- **Tailscale Talos extension (`tailscale_auth_key` passthrough + `ExtensionServiceConfig`)** — commented out (not deleted) in 7 `variables.tf` (`modules/talos-cluster`, `modules/proxmox`, `modules/libvirt`, `environments/proxmox/{dev,prod}`, `environments/libvirt/{dev,prod}`), 2 `ExtensionServiceConfig` blocks in `modules/talos-cluster/main.tf` (`TS_ACCEPT_DNS=true` for control-plane, `false` for workers), and 6 passthrough assignments (`modules/proxmox/main.tf:197`, `modules/libvirt/cluster.tf:52`, `environments/proxmox/{dev,prod}/main.tf:20`, `environments/libvirt/{dev,prod}/main.tf:23`). Header `Tailscale extension disabled - see docs/adr/001-remove-tailscale-extension.md / To enable: uncomment this variable AND uncomment siderolabs/tailscale in schematic-*.yaml`; keeps HCL valid (`#` comment) and one-liner restore without injecting config for a missing extension
- **`scripts/destroy-tailscale-devices.sh` (124 lines)** — deleted; `curl` OAuth + `hostname` exact-match device deletion is obsolete without node-registered Tailscale devices. CI and `just tf-destroy` no longer call it
- **CI tfstate artifact handling (`tfstate-${TF_ROOT}-${TF_ENV}`)** — removed `Restore Terraform state from last successful run` (`gh api` + `unzip` of `tfstate-proxmox-prod`) and `Backup Terraform state` (`upload-artifact@v4`) from both `deploy.yaml` and `destroy.yaml`; state now lives only in S3 RustFS (`terraform-homelab` bucket, `proxmox/prod/terraform.tfstate` + `libvirt/prod/terraform.tfstate` via `backend "s3"`); `environments/**/terraform.tfstate` local copies are stale and ignored

### Fixed
- **Bootstrap-only `talos_machine_secrets` (`modules/proxmox` and `modules/libvirt`)** — added `lifecycle { ignore_changes = [talos_version] }` so bumping `talos_version` (upgrade or downgrade) no longer rotates the CA. In-place upgrades now flow solely through `talos_machine.image` (`factory.talos.dev/nocloud-installer*:<id>:v<version>`) as a sequential rolling reboot, preventing `x509: certificate signed by unknown authority (Ed25519 verification failure)` after version changes
- **`talos_cluster` health hang (`modules/talos-cluster/main.tf`)** — reverted experimental `control_plane_nodes = [var.cp_ips[0]]` (single-node fast bootstrap) that caused `context deadline exceeded` 10m hang; restored `var.cp_ips` (3 nodes, 15m/30m) — HA bootstrap now completes in ~7m57s as before; `talos_cluster_health` remains the HA gate
- **Health gate timeout (`modules/proxmox/main.tf`, `modules/libvirt/cluster.tf`)** — `read = "5m" → "10m"` so `kube-controller-manager` has time to become Ready after etcd `Preparing`; also fixed `Warning: Check block assertion known after apply` by removing `check` and using `data` with `count`
- **Ephemeral `local_file` write (`environments/*/main.tf`)** — dropped `ephemeral "talos_cluster_kubeconfig"` for `local_file.kubeconfig` (hashicorp/local#373 lacks `content_wo`); kept `resource "talos_cluster_kubeconfig"` live retrieval for now

### Changed
- **Breaking: platform composed into environments** — `environments/proxmox/{dev,prod}/main.tf` and `environments/libvirt/{prod,dev}/main.tf` now compose `module "platform"` (`source = ../../../modules/platform`, `kubeconfig_path = abspath("${path.root}/../../../secrets/...")`, `argocd_version`, `depends_on = [data.talos_cluster_health.this]` / `module.proxmox/libvirt`). Each `environments/<provider>/<env>/provider.tf` now declares `helm ~>2.0` and configures `provider helm` with `config_path`. Each `variables.tf` adds `argocd_version` (default 9.5.13).
- **Justfile** — `tf-platform-*` tasks are deprecated wrappers delegating to standard `tf-*` tasks; header updated to document composed model. Single `just tf-apply` now provisions cluster + ArgoCD.
- **CI `deploy.yaml` (149 → 109 lines, S3 simplification)** — triggers now `push` + `pull_request` without branch filter (validate on all branches), `deploy` job gated by `if: github.ref == 'refs/heads/main' || github.event_name == 'workflow_dispatch'`; removed `Restore Terraform state` (28 lines `gh api` + artifact) and `Backup Terraform state` + `upload-artifact: tfstate-*`; `terraform init -reconfigure` and `terraform apply` now inject `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for RustFS S3 backend; removed `TF_VAR_tailscale_auth_key` (extension disabled — subnet routing kept via `tailscale/github-action@v4` with `TS_OAUTH_*`); keeps `Extract cluster secrets` + `cluster-secrets-${TF_ENV}` artifact; single `terraform apply` in `environments/${TF_ROOT}/${TF_ENV}`, validate now covers `modules/platform`
- **CI `destroy.yaml` (111 → 59 lines, minimal rewrite)** — removed job-level `env: TS_OAUTH_CLIENT_ID/SECRET`, removed `Restore Terraform state` (bug: `environments/${TF_ENV}` without `TF_ROOT` + `working-directory: ${TF_ROOT}`), removed `Clean up Tailscale devices` step (`./scripts/destroy-tailscale-devices.sh lonk-mirfak` hardcode), removed `Backup Terraform state` + `upload-artifact`; fixed `working-directory` to `environments/${TF_ROOT}/${TF_ENV}` (aligned with `deploy.yaml`), removed legacy `-backend-config="path=..."` / `-var-file=...` flags; `Connect to Tailscale` now uses direct `secrets.TS_OAUTH_*`; `terraform init -reconfigure` + `terraform destroy -auto-approve` now inject `AWS_*` + `TF_VAR_api_token` + `TF_VAR_enable_health_check="false"` only (no `tailscale_auth_key`); `tailscale/github-action` kept for subnet-route reachability to `10.10.0.0/24`
- **CI (`deploy.yaml`) legacy** — previously removed separate platform restore/apply/backup steps; single `terraform apply` in `environments/${TF_ROOT}/${TF_ENV}` (artifact `tfstate-${TF_ROOT}-${TF_ENV}`), validate now covers `modules/platform` (superseded by S3 simplification above).
- **`schematic-prod.yaml`** — expanded comment above `# - siderolabs/tailscale` to `To re-enable Tailscale on nodes: uncomment below AND uncomment tailscale_auth_key in variables.tf / main.tf - see ADR docs/adr/001-remove-tailscale-extension.md` (keeps YAML valid, documents restore without re-enabling the extension)
- **README.md** — Structure, Platform (ArgoCD), Setup flow, State, and Available tasks sections rewritten for single-state composed model; `platform/` as deprecated removed.
- **Modularized Libvirt root** — decomposed monolithic `libvirt/main.tf` into domain-focused files: `network.tf` (NAT network & DHCP), `image.tf` (Talos factory schematic & cache download), `vms.tf` (volumes & KVM domains), `cluster.tf` (bootstrap module & health gate), and `pool.tf` (storage pool)
- **Deterministic MAC generation in Libvirt** (`libvirt/variables.tf`, `libvirt/vms.tf`, `libvirt/network.tf`) — made `mac` optional in `nodes_cp` / `nodes_worker`; when omitted, a stable QEMU OUI MAC (`52:54:00:xx:yy:zz`) is auto-generated deterministically from `md5(hostname)`, eliminating hardcoded MAC addresses in `terraform.tfvars`
- **Eliminated Cloud-Init duplication in Libvirt** (`libvirt/vms.tf`, `libvirt/cluster.tf`) — removed redundant `libvirt_cloudinit_disk` and permanent ISO CD-ROM mounts; node IP/DNS assignment is handled natively by Libvirt DHCP reservations (`libvirt_network.talos`), and all machine configs/patches (VIP, scheduling, Longhorn, Tailscale) are delegated exclusively to `module.talos_cluster`
- **Removed fragile `wait_for_cp` local-exec** (`libvirt/cluster.tf`) — replaced raw `/dev/tcp` shell polling with native Terraform provider resource dependencies (`depends_on = [libvirt_domain.node]` on `module.talos_cluster` and `talos_machine` gRPC retry logic)
- **Persistent Talos image cache** (`libvirt/variables.tf`, `libvirt/image.tf`) — moved default raw cache directory from `/tmp/talos-images` to `~/.cache/talos-images` with permissions fix (`chmod 644`) to prevent host reboot cache wipes and permission errors
- **Domain recreation lifecycle** (`libvirt/vms.tf`) — bound boot volume ID to `libvirt_domain` metadata to ensure clean VM recreation during base image and SecureBoot transitions
- **Bootstrap-only Libvirt base image** (`libvirt/image.tf`, `libvirt/vms.tf`) — decoupled `talos_version` and schematic updates from VM disk destruction using fixed image filenames and `lifecycle { ignore_changes = [create] }`, matching Proxmox behavior where in-place OS upgrades are handled solely by `talos_machine.image`
- **Breaking: `allow_scheduling_on_control_planes` removed** — replaced by a required per-node `allow_scheduling` flag on `nodes_cp` entries. The `talos-cluster` module now takes `cp_allow_scheduling` (index-aligned with `cp_hostnames` / `cp_ips`) and patches each control plane's Talos machine config with `cluster.allowSchedulingOnControlPlanes: true` (per Sidero docs), so the kubelet never registers the `node-role.kubernetes.io/control-plane` taint — durable across node reboots, no `kubectl` requirement
- **Breaking: per-node disk/datastore are now required** — `nodes_cp` / `nodes_worker` require per-node `disk_size` (GB) and `datastore` (Proxmox) / `pool` (libvirt); the global `disk_size_cp`, `disk_size_worker` and `datastore_vm` variables were removed, so there are no fallback defaults
- `talos_version` is now managed declaratively via `talos_machine.image` in `modules/talos-cluster/main.tf` — `proxmox/variables.tf` (default `1.13.9`) and `libvirt/variables.tf` (default `1.13.8`) bump triggers a sequential rolling upgrade (`terraform apply -parallelism=1`, `drain_on_upgrade = false`) instead of VM recreation; `proxmox_download_file.talos_image` is now bootstrap-only with `lifecycle { ignore_changes = [url] }`
- Talos Linux default `1.13.6` → `1.13.8` (both roots)
- `README.md` — corrected stale version defaults (`talos_version` 1.13.3 → 1.13.8, `kubernetes_version` 1.36.1 → 1.36.2)
- `README.md` — new "Plataforma (ArgoCD)" section: setup flow (`tf-apply` → `tf-platform-apply` → GitOps bootstrap), plus the Longhorn migration runbook (`terraform state rm` before applying the reduced layer, never `terraform destroy`)
- `README.md` — documented the SDN network reachability requirement: the `talosvn` VNet is isolated (outbound SNAT only), so the machine running `terraform apply` must reach `10.10.0.0/24`; for `prod` the subnet is exposed via a Tailscale subnet router (`tailscale set --advertise-routes=10.10.0.0/24` on the Proxmox host, approve in admin console, `--accept-routes` on Linux clients)
- `proxmox/environments/{dev,prod}/terraform.tfvars` — network bridge renamed `vnet1` → `talosvn`; new `sdn_zone` / `network_cidr` variables; `cluster_vip` corrected to `10.10.0.171` (was outside the `10.10.0.0/24` subnet)
- `proxmox/main.tf` — VM IP prefix/mask now derived from `network_cidr` instead of a hardcoded `/24`
- `proxmox/variables.tf` — added `sdn_zone`, `network_cidr`, `network_mtu`, `network_snat` variables; `network_bridge` doc updated for SDN usage
- **Longhorn moved to the GitOps repo** — deployed by `secured-gitops-tailscale-homelab` as a wave-0 ArgoCD app (`platform/longhorn`) with a CSI readiness gate (Job `longhorn-csi-wait`); `platform/` no longer installs Longhorn previously (`kubernetes_namespace_v1.longhorn_system`, `helm_release.longhorn`, `terraform_data.csi_waiter` removed) before its full deletion in this refactor
- **Runbook for migration** — README documents `terraform state rm` for the old Longhorn resources before applying the reduced layer, so volumes are never destroyed (never `terraform destroy` `helm_release.longhorn`)
- **Justfile unified around `provider=` / `tf_env=`** — one task set now serves both providers; the dedicated libvirt tasks (`tf-libvirt-*`, `gen-libvirt-secrets`, `setup-libvirt-cli`, `upgrade-libvirt`) were removed. Backend/var-file arguments, secrets path, and status labels are derived from the active provider/env; platform tasks no longer chain `gen-secrets` or pass backend/`env_name` flags
- `justfile` — comments and task descriptions fully translated to English
- `README.md` — task tables and quick-start examples updated to the unified `just` task set; platform setup flow and state notes updated; Longhorn migration runbook translated to English
- `talos_version` default `1.13.8` → `1.13.9` in `proxmox/variables.tf` (libvirt stays `1.13.8`)
- `justfile` `tf-apply` now runs `terraform apply -parallelism=1` — sequential reboots protect etcd quorum during `talos_machine` rolling upgrades; cold bootstrap from scratch is slower (~15 min × 3) but safe
- `proxmox/main.tf` `proxmox_download_file.talos_image` is now bootstrap-only: `file_name` simplified from `talos-${env}-v${version}-nocloud-amd64-secureboot.img` to `talos-nocloud-amd64-secureboot.img` (shared, no `env`/`version` suffix) and `lifecycle { ignore_changes = [url] }` so bumping `talos_version` or changing the schematic no longer recreates the disk/etcd — upgrades flow through `talos_machine.image`
- `modules/talos-cluster/main.tf` installer image flavor `factory.talos.dev/installer-secureboot/...` → `factory.talos.dev/nocloud-installer-secureboot/${talos_image_id}:v${talos_version}` with new `local.installer_image` that respects `var.installer_image`
- `modules/talos-cluster/main.tf` / `outputs.tf` locals renamed `tailscale_cp_names` → `cp_names`, `tailscale_worker_names` → `worker_names`, `all_tailscale_names` → `all_nodes_names`
- `modules/talos-cluster/main.tf` — `locals.cp_names` / `locals.worker_names` simplified from conditional FQDN (`var.tailscale_domain != "" ? ["${hostname}.${var.tailscale_domain}"] : []`) to direct `var.cp_hostnames` / `var.worker_hostnames`; domain suffix no longer appended
- `environments/proxmox/{dev,prod}/terraform.tfvars` — `endpoint` changed from `https://pve01.lonk-mirfak.ts.net:8006` to `https://pve01.lonk-mirfak.ts.net` (port omitted, falls back to provider default 8006) and `ssh_node_address` shortened from `pve01.lonk-mirfak.ts.net` to `pve01` (relies on Tailscale MagicDNS / SSH host alias)
- `environments/proxmox/prod/terraform.tfvars` — `insecure = true` removed; TLS verification now defaults to `false` (`variable "insecure"` default `false` in `environments/proxmox/prod/variables.tf` / `provider.tf`), secure-by-default — set explicitly if you need self-signed certs
- `environments/proxmox/{dev,prod}/variables.tf` — `variable "ssh_node_address"` description example updated `node.lonk-mirfak.ts.net` → `node.tail-scale.ts.net`
- `README.md` — Tailscale domain examples updated `lonk-mirfak.ts.net` → `tail-scale.ts.net` (Proxmox and Libvirt variable tables)
- **Prod cluster topology (commented tfvars)** — `environments/proxmox/prod/terraform.tfvars` and `environments/libvirt/prod/terraform.tfvars` flipped for HA testing: 3 control-plane nodes active (`talos-cp2` / `talos-cp3` uncommented, `allow_scheduling = true`, libvirt memory 6 GB) and all workers commented out (previously 1 CP + 3 workers active, cp2/cp3 commented)
- **Terraform `required_version` `>=1.11` (`environments/*/provider.tf`, `modules/*/provider.tf`)** — bumped from `>=1.5` for TF 1.15.9 write-only/ephemeral support; `talos` pinned `0.12.0-alpha.5` with `kubernetes_version` now owned by `talos_cluster` (`ignore_kubernetes_upgrade_drift = true` on `talos_machine`)
- **`talos_machine_bootstrap` → `talos_cluster` (`modules/talos-cluster/main.tf`)** — `depends_on = [talos_machine.control_plane]`, `node = var.cp_ips[0]`, `control_plane_nodes = var.cp_ips`, `timeouts = { create = "15m", update = "30m" }`; `data "talos_machine_configuration"` no longer sets `kubernetes_version`; workers now `depends_on = [talos_cluster.cluster]`; `resource "talos_cluster_kubeconfig"` live retrieval replaces deprecated `data "talos_cluster_kubeconfig"`
- **Bootstrap settle `45s → 10s` (`modules/proxmox/main.tf`, `modules/libvirt/cluster.tf`)** — `time_sleep.post_bootstrap` reduced; `talos_cluster` already polls, health gate handles HA wait
- **Justfile `tf-apply` parallelism** — `tf-apply` now `apply -parallelism=10` (fast bootstrap, ~8m end-to-end vs 12m); new `tf-apply-upgrade` with `-parallelism=1` for `talos_version` rolling upgrades (protects etcd quorum); `tf-destroy` uses `TF_VAR_enable_health_check=false`
- **Provider version bumps (`environments/*/provider.tf`)** — `hashicorp/helm` `~> 2.0` → `~> 2.17`, `hashicorp/local` `~> 2.0` → `~> 2.9`, `hashicorp/time` `~> 0.9` → `~> 0.14`; added `hashicorp/kubernetes` `~> 2.38` to `required_providers` (all 4 envs) so `provider helm.kubernetes` resolves its schema and VSCode `terraform-ls` stops reporting `Blocks of type "kubernetes" are not expected here`

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
