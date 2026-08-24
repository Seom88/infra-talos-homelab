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
}

# ── Platform layer (ArgoCD) — composable module ──────────────────────────
module "platform" {
  source = "../../../modules/platform"

  kubeconfig_path = abspath("${path.root}/../../../secrets/libvirt/${var.env_name}/kubeconfig.yaml")
  argocd_version  = var.argocd_version

  depends_on = [module.libvirt]
}
