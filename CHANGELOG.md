# Changelog

All notable changes to this project will be documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
