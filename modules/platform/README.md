# platform module

Composable Terraform module that installs the **platform layer** (currently ArgoCD) on top of a Talos Kubernetes cluster. It is intended to be called from each environment root (`environments/<provider>/<env>`), not as a standalone root.

## What it does

1. **Node readiness gate** (`terraform_data.wait_nodes`) — waits for all nodes to be `Ready` via `kubectl wait`. This is Layer 2; Layer 1 is the `talos_cluster_health` gate in the infra module (`modules/proxmox` / `modules/libvirt`).
2. **ArgoCD** (`helm_release.argocd`) — installs the `argo-cd` chart from `https://argoproj.github.io/argo-helm`.

## Usage

The calling root **must** configure the `helm` provider. Example for `environments/proxmox/prod`:

```hcl
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path = abspath("${path.root}/../../../secrets/proxmox/${var.env_name}/kubeconfig.yaml")
  }
}

module "platform" {
  source          = "../../../modules/platform"
  kubeconfig_path = abspath("${path.root}/../../../secrets/proxmox/${var.env_name}/kubeconfig.yaml")
  argocd_version  = var.argocd_version
  depends_on      = [module.proxmox] # ensures talos_cluster_health has passed
}
```

## Inputs

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `kubeconfig_path` | string | — (required) | Path to kubeconfig file. Re-triggers `wait_nodes` via `filesha256` when it changes. If file missing, trigger is `kubeconfig-missing`. |
| `argocd_version` | string | `9.5.13` | Exact ArgoCD chart version. |
| `argocd_namespace` | string | `argocd` | Namespace for ArgoCD. |
| `argocd_values_file` | string | `""` → `values/argocd/values.yaml` | Custom Helm values file path. |

## Outputs

- `argocd_namespace`, `argocd_version`, `argocd_release_name`

## Kubeconfig handling

The helm provider's `config_path` must point to a file that exists at apply time. In this repo the file is at `secrets/<provider>/<env>/kubeconfig.yaml` and is materialized by `just gen-secrets` (`terraform output -raw kubeconfig > secrets/.../kubeconfig.yaml`). The `talos_cluster_health` + `wait_nodes` chain ensures the cluster is ready before Helm runs. On a cold `just tf-apply`, the single state file now deploys both infra and platform — no separate `platform` state is needed.

## Migration from `platform/` root

The standalone root at `platform/` is deprecated. To migrate existing state:

```bash
# From repo root, after updating code:
terraform -chdir=environments/proxmox/prod init -reconfigure
terraform -chdir=platform init -reconfigure -backend-config="path=environments/proxmox/prod/terraform.tfstate"

# Move the Helm release into the composed state:
terraform -chdir=environments/proxmox/prod state mv \
  'helm_release.argocd' \
  'module.platform.helm_release.argocd'

# Move the wait_nodes gate if you want history preserved:
terraform -chdir=environments/proxmox/prod state mv \
  'terraform_data.wait_nodes' \
  'module.platform.terraform_data.wait_nodes'

# Verify and remove deprecated platform state:
terraform -chdir=environments/proxmox/prod plan
rm -rf platform/environments
```

Replace `proxmox/prod` with your `provider/env`.
