# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
