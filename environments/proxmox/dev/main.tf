module "proxmox" {
  source = "../../../modules/proxmox"

  env_name         = var.env_name
  node_name        = var.node_name
  ssh_username     = var.ssh_username
  ssh_node_address = var.ssh_node_address
  gateway          = var.gateway
  datastore_iso    = var.datastore_iso
  network_bridge   = var.network_bridge
  sdn_zone         = var.sdn_zone
  network_cidr     = var.network_cidr
  network_mtu      = var.network_mtu
  network_snat     = var.network_snat
  nodes_cp         = var.nodes_cp
  nodes_worker     = var.nodes_worker
  talos_version    = var.talos_version

  cluster_name         = var.cluster_name
  kubernetes_version   = var.kubernetes_version
  longhorn_enabled     = var.longhorn_enabled
  extra_config_patches = var.extra_config_patches
  install_disk_match   = var.install_disk_match

  default_datastore      = var.default_datastore
  default_data_datastore = var.default_data_datastore

  # Tailscale disabled - see ADR 001
  # tailscale_auth_key  = var.tailscale_auth_key
  enable_health_check = var.enable_health_check
  drain_on_upgrade    = var.drain_on_upgrade
}

# Kubeconfig: fresh output before platform (avoids stale CA).
resource "local_file" "kubeconfig" {
  content         = module.proxmox.kubeconfig
  filename        = abspath("${path.root}/../../../secrets/proxmox/${var.env_name}/kubeconfig.yaml")
  file_permission = "0600"

  depends_on = [module.proxmox]
}

# Platform (ArgoCD)
module "platform" {
  source = "../../../modules/platform"

  kubeconfig_path = abspath("${path.root}/../../../secrets/proxmox/${var.env_name}/kubeconfig.yaml")
  kubeconfig_hash = local_file.kubeconfig.content_base64sha256
  argocd_version  = var.argocd_version

  # Dev: full observability — base prod (values.yaml) + hubble ON via overlay
  cilium_values_file = "${path.module}/../../../modules/platform/values/cilium/values-dev.yaml"

  depends_on = [local_file.kubeconfig]
}
