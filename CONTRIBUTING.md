# Contributing to infra-talos-homelab

Thanks for your interest in contributing! This guide will help you get started.

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Terraform](https://www.terraform.io/downloads) | >= 1.5 | Infrastructure provisioning |
| [just](https://github.com/casey/just) | latest | Task runner |
| [Talosctl](https://www.talos.dev/v1.13/introduction/get-started/) | matching `talos_version` | Cluster management |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | latest | Kubernetes CLI |
| [jq](https://stedolan.github.io/jq/) | latest | JSON processing |

### Provider-specific requirements

- **Proxmox**: Proxmox VE 8.x with API token access. See [bpg/proxmox docs](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) for auth setup.
- **Libvirt**: Linux host with libvirt + KVM. The `qemu:///system` connection must be accessible without password.

## Getting started

```bash
# Clone the repo
git clone https://github.com/Seom88/infra-talos-homelab.git
cd infra-talos-homelab

# Pick your provider and environment
just tf_env=dev tf-apply      # Proxmox dev
just tf-apply                  # Proxmox prod
just tf-libvirt-apply          # Libvirt
```

## Development workflow

1. **Fork** the repository
2. **Create a branch** from `main` (`git checkout -b feat/my-feature`)
3. **Make your changes** — follow the conventions below
4. **Format** before committing: `just tf-fmt` (runs `terraform fmt -recursive`)
5. **Validate**: `terraform validate` in the relevant directory
6. **Open a PR** against `main`

## Conventions

### Terraform

- Pin provider versions explicitly (exact for critical providers, `~>` for others)
- Use `for_each` over `count` for node resources (clearer addressing)
- Name resources descriptively: `talos_machine_configuration_apply.control_machine_config_apply`
- Keep provider-specific logic in root modules (`proxmox/`, `libvirt/`), not in shared modules

### Secrets

- Never commit `secrets/` — it is `.gitignored` by default
- Never commit `.tfvars` with real credentials
- CI uses GitHub Secrets for Proxmox tokens and Tailscale auth keys

### Commits

- Use [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `refactor:`, etc.
- Keep commits focused on one logical change
- Reference issues when applicable (`fixes #42`)

## Project structure

```
proxmox/                 # Proxmox VE root module
libvirt/                 # Libvirt root module
modules/talos-cluster/   # Provider-agnostic Talos module
schematic-*.yaml         # Talos Image Factory extension bundles
.github/workflows/       # CI/CD
```

## Reporting issues

Open a GitHub issue with:

- Provider and version (`bpg/proxmox 0.109.0`, `dmacvicar/libvirt 0.9.8`, etc.)
- Terraform version
- Talos Linux version
- Steps to reproduce
- Expected vs actual behavior

## Questions?

Open a discussion on GitHub or reach out via the project's LinkedIn post.
