module "libvirt" {
  source = "../../../modules/libvirt"

  nodes_cp     = var.nodes_cp
  nodes_worker = var.nodes_worker
  pool_name    = var.pool_name
  pool_path    = var.pool_path

  gateway      = var.gateway
  network_cidr = var.network_cidr

  # Schematic path resolved relative to the repo root (3 levels up from this environment)
  schematic_path = "${path.module}/../../../schematic-${var.env_name}.yaml"

  secureboot            = var.secureboot
  ovmf_code_secboot     = var.ovmf_code_secboot
  ovmf_vars_secboot     = var.ovmf_vars_secboot
  talos_image_cache_dir = var.talos_image_cache_dir

  cluster_name         = var.cluster_name
  talos_version        = var.talos_version
  kubernetes_version   = var.kubernetes_version
  tailscale_auth_key   = var.tailscale_auth_key
  longhorn_enabled     = var.longhorn_enabled
  extra_config_patches = var.extra_config_patches
  enable_health_check  = var.enable_health_check
}

# ── Kubeconfig auto-generation (avoids stale file race) ──────────────────
# Writes the fresh kubeconfig from the infra module to the canonical secrets
# path BEFORE the platform layer runs. Without this, the helm provider and
# platform wait_nodes gate read a stale on-disk kubeconfig from a previous
# cluster (stale CA → x509: certificate signed by unknown authority).
# `just gen-secrets` remains as a manual fallback / setup-cli helper.
resource "local_file" "kubeconfig" {
  content         = module.libvirt.kubeconfig
  filename        = abspath("${path.root}/../../../secrets/libvirt/${var.env_name}/kubeconfig.yaml")
  file_permission = "0600"

  depends_on = [module.libvirt]
}

# ── Platform layer (ArgoCD) — composable module ──────────────────────────
module "platform" {
  source = "../../../modules/platform"

  kubeconfig_path = abspath("${path.root}/../../../secrets/libvirt/${var.env_name}/kubeconfig.yaml")
  kubeconfig_hash = local_file.kubeconfig.content_base64sha256
  argocd_version  = var.argocd_version

  depends_on = [local_file.kubeconfig]
}
