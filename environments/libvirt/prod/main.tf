module "libvirt" {
  source = "../../../modules/libvirt"

  nodes_cp     = var.nodes_cp
  nodes_worker = var.nodes_worker
  pool_name    = var.pool_name
  pool_path    = var.pool_path

  gateway      = var.gateway
  network_cidr = var.network_cidr

  schematic_path = "${path.module}/../../../schematic-${var.env_name}.yaml"

  secureboot            = var.secureboot
  ovmf_code_secboot     = var.ovmf_code_secboot
  ovmf_vars_secboot     = var.ovmf_vars_secboot
  talos_image_cache_dir = var.talos_image_cache_dir

  cluster_name       = var.cluster_name
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  # Tailscale disabled - see ADR 001
  # tailscale_auth_key   = var.tailscale_auth_key
  longhorn_enabled     = var.longhorn_enabled
  extra_config_patches = var.extra_config_patches
  enable_health_check  = var.enable_health_check
  drain_on_upgrade     = var.drain_on_upgrade
}

# Kubeconfig: fresh output before platform (avoids stale CA).
resource "local_file" "kubeconfig" {
  content         = module.libvirt.kubeconfig
  filename        = abspath("${path.root}/../../../secrets/libvirt/${var.env_name}/kubeconfig.yaml")
  file_permission = "0600"

  depends_on = [module.libvirt]
}

# Platform (ArgoCD + Cilium)
module "platform" {
  source = "../../../modules/platform"

  kubeconfig_path = abspath("${path.root}/../../../secrets/libvirt/${var.env_name}/kubeconfig.yaml")
  kubeconfig_hash = local_file.kubeconfig.content_base64sha256
  argocd_version  = var.argocd_version

  # Cilium operator: 2 replicas for prod HA (3 CPs) — leader election active/standby
  cilium_operator_replicas = 2

  depends_on = [local_file.kubeconfig]
}
