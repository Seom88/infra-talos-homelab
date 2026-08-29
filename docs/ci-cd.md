# CI / CD

> GitHub Actions, validation matrix, formatting, and Renovate — how quality is enforced and dependencies stay fresh.

[← Back to README](../README.md) · [Architecture →](./architecture.md) · [Usage →](./usage.md)

## Workflows

Both workflows live in `.github/workflows/` and use `hashicorp/setup-terraform@v4` with `terraform_wrapper: false`.

### `deploy.yaml` — Validate → Deploy

Triggers: `push` + `pull_request` (all branches), `workflow_dispatch`. Deploy gated to `main` only.

| Job | Runs | What it does |
|-----|------|--------------|
| `fmt` | always | `terraform fmt -check -diff -recursive` from repo root |
| `validate` | after `fmt` | 4-env matrix (see below) + platform module checks |
| `deploy` | only `main` / manual, after `validate` | Single `terraform apply` (infra + platform, one state) |

**Validate matrix** — fans out to 4 environments with `terraform init -backend=false` + `terraform validate -no-color` (no S3 creds needed):

| `tf_root` | `tf_env` | Backend | Extra checks |
|-----------|----------|---------|--------------|
| `proxmox` | `prod` | s3 (RustFS) | + platform `fmt` + platform `init -backend=false` / `validate` |
| `proxmox` | `dev`  | local | — |
| `libvirt` | `prod` | s3 (RustFS) | — |
| `libvirt` | `dev`  | local | — |

```yaml
# .github/workflows/deploy.yaml — validate matrix
strategy:
  matrix:
    include:
      - { tf_root: proxmox, tf_env: prod }
      - { tf_root: proxmox, tf_env: dev }
      - { tf_root: libvirt, tf_env: prod }
      - { tf_root: libvirt, tf_env: dev }
steps:
  - run: terraform init -backend=false
        terraform validate -no-color
    working-directory: environments/${{ matrix.tf_root }}/${{ matrix.tf_env }}
  - if: matrix.tf_root == 'proxmox' && matrix.tf_env == 'prod'
    run: terraform fmt -check -diff -recursive  # modules/platform
  - if: matrix.tf_root == 'proxmox' && matrix.tf_env == 'prod'
    run: terraform init -backend=false && terraform validate  # modules/platform
```

Local equivalent: `just tf-validate` (same loop, no creds). Full CI locally: `just tf-ci` (`tf-fmt-check` + `tf-validate`).

**Deploy job** (`runs-on: ubuntu-latest`, `environment: prod`, `concurrency: tf-deploy-${{ github.ref_name }}`):

1. `checkout` + `setup-terraform` + `setup-kubectl` + `setup-helm`
2. `mkdir -p secrets/<TF_ROOT>/<TF_ENV> && touch kubeconfig.yaml` — placeholder so `helm` provider can `init`
3. `tailscale/github-action@v4` with `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_SECRET` (`tags: tag:terraform`) — subnet-route reachability to `10.10.0.0/24` (no Tailscale extension on nodes, see [ADR 001](./adr/001-remove-tailscale-extension.md))
4. `terraform init -reconfigure` in `environments/${TF_ROOT}/${TF_ENV}` with `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (RustFS S3 `terraform-homelab` bucket, path-style, `skip_*` for S3-compatible API)
5. `terraform output -raw kubeconfig > .../kubeconfig.yaml` — restore kubeconfig from state (keeps placeholder if no prior state)
6. `terraform apply -parallelism=1 -auto-approve -no-color` with `TF_VAR_api_token: ${{ secrets.PROXMOX_API_TOKEN }}` (certs scrubbed via `sed -E 's/[A-Za-z0-9+/=]{80,}/***CERT***/g'`)

> The single `terraform apply` deploys both infra (`module.proxmox` / `module.libvirt` + `talos_cluster`) and platform (`module.platform` → `helm_release.argocd`) in one state file at `environments/<provider>/<env>/terraform.tfstate`. See [Platform](./platform.md).

**Required GitHub secrets:**

| Secret | Value |
|--------|-------|
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client ID (`tag:terraform`, scopes `devices:core:write` + `auth_keys:write`) |
| `TS_OAUTH_SECRET` | Tailscale OAuth client secret |
| `PROXMOX_API_TOKEN` | Proxmox API token (`user@realm!tokenid=secret`) |
| `AWS_ACCESS_KEY_ID` | RustFS S3 access key |
| `AWS_SECRET_ACCESS_KEY` | RustFS S3 secret key |

To use from a fork, also configure `tagOwners` / `acls` / `ssh` for `tag:terraform → tag:pve` in your Tailscale ACL (see original README CI/CD section and `deploy.yaml` env `TF_ROOT=proxmox TF_ENV=prod`).

### `destroy.yaml` — Manual destroy

Trigger: `workflow_dispatch` with `confirm == "destroy"`. Concurrency `tf-deploy-*`, `environment: prod`.

Steps: `checkout` → `setup-terraform` → placeholder `kubeconfig.yaml` → `tailscale/github-action@v4` → `terraform init -reconfigure` (AWS creds) → `terraform output -raw kubeconfig > ...` → `terraform destroy -auto-approve` with `TF_VAR_api_token` + `TF_VAR_enable_health_check="false"` (so `data.talos_cluster_health` does not block destroy). The working directory is `environments/${TF_ROOT}/${TF_ENV}` (aligned with `deploy.yaml`).

## Quality gates

| Gate | How | Where |
|------|-----|-------|
| Format | `terraform fmt -check -diff -recursive` | `deploy.yaml:fmt`, `just tf-fmt-check` |
| Validate | `terraform init -backend=false` + `terraform validate` × 4 envs + platform | `deploy.yaml:validate`, `just tf-validate` |
| Input validation | 57 blocks (semver, CIDR, IP, `^(dev\|prod)$`, nullable guards) | `modules/*`, `environments/*` — see [Variables](./variables.md) |
| Full local CI | `just tf-ci` | `justfile` |
| Hardened inputs | `drain_on_upgrade`, `enable_health_check`, explicit pins | [Variables](./variables.md), [Operations](./operations.md) |

## Renovate

`renovate.json` runs weekly **Monday 05:00 `Europe/Madrid`**, `config:recommended`, labels `dependencies`:

| Rule | Datasource | Group / Label | Automerge |
|------|------------|---------------|-----------|
| Pinned talos provider alpha until #352 fixed — ADR 002 | `terraform-provider` `siderolabs/talos` | `allowedVersions: =0.12.0-alpha.5`, `enabled: false` | — |
| Talos upgrades need manual validation in `libvirt/dev` first | `github-releases` `siderolabs/talos` | `manual-review/talos` | `false` |
| ArgoCD Helm chart upgrades need manual review | `helm` `argo-cd` | `manual-review/argocd` | `false` |
| Group non-critical Terraform providers | `terraform` `terraform-provider` excl. `siderolabs/talos` | `terraform providers` (`terraform-providers`), `terraform` | grouped PR |

**Custom managers** (regex on `variables.tf`):

- `talos_version` (`variable "talos_version" ... default = "x.y.z"`) → `github-releases/siderolabs/talos`, semver
- `argocd_version` (`variable "argocd_version" ... default = "x.y.z"`) → `helm/argo-cd` via `https://argoproj.github.io/argo-helm`, semver

`kubernetes_version` is intentionally **not** managed by Renovate — owned by `talos_cluster.kubernetes_version` with `ignore_kubernetes_upgrade_drift = true` (see `modules/talos-cluster/main.tf:124,184`). Validate Talos upgrades in `libvirt/dev` before merging to prod.

---

Next: [Architecture →](./architecture.md) · [Networking →](./networking.md) · [Variables →](./variables.md)
