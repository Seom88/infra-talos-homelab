# ============================================================
# Talos Machine Secrets
# ============================================================

resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"
}

# ============================================================
# Talos Cluster — apply, bootstrap, kubeconfig
# ============================================================

module "talos_cluster" {
  source = "../talos-cluster"

  machine_secrets      = talos_machine_secrets.this.machine_secrets
  client_configuration = talos_machine_secrets.this.client_configuration
  cp_ips               = [for n in var.nodes_cp : n.ip]
  cp_hostnames         = [for n in var.nodes_cp : n.hostname]
  worker_ips           = [for n in var.nodes_worker : n.ip]
  worker_hostnames     = [for n in var.nodes_worker : n.hostname]
  cluster_name         = var.cluster_name
  talos_version        = var.talos_version
  kubernetes_version   = var.kubernetes_version
  talos_image_id       = talos_image_factory_schematic.this.id
  secureboot           = var.secureboot
  tailscale_domain     = var.tailscale_domain
  tailscale_auth_key   = var.tailscale_auth_key
  cp_allow_scheduling  = [for n in var.nodes_cp : n.allow_scheduling]
  longhorn_enabled     = var.longhorn_enabled
  extra_config_patches = var.extra_config_patches

  depends_on = [libvirt_domain.node]
}

# ── Cluster Health Gate ─────────────────────────
# Blocks apply until kube-apiserver, etcd, and all nodes are Ready,
# so dependent roots (platform/) never race the cluster bootstrap.
data "talos_cluster_health" "this" {
  depends_on           = [module.talos_cluster]
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [for node in var.nodes_cp : node.ip]
  worker_nodes         = [for node in var.nodes_worker : node.ip]
  endpoints            = [for node in var.nodes_cp : node.ip]
  timeouts = {
    read = "15m"
  }
}
