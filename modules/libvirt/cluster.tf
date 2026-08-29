locals {
  has_data_disk = length([for n in concat(var.nodes_cp, var.nodes_worker) : n if try(n.data_disk_size, null) != null]) > 0
  # UserVolumeConfig "data" -> /var/mnt/data (generic); "!system_disk" suffices for virtio.
  data_volume_patch = local.has_data_disk ? yamlencode({
    apiVersion = "v1alpha1"
    kind       = "UserVolumeConfig"
    name       = "data"
    provisioning = {
      diskSelector = { match = "!system_disk" }
      grow         = false
      minSize      = "10GB"
    }
  }) : ""
}

# Talos machine secrets (bootstrap-only)
resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"

  # Bootstrap-only: version bumps must not rotate CA.
  lifecycle {
    ignore_changes = [talos_version]
  }
}

# Talos cluster

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
  # Tailscale disabled - see ADR 001
  # tailscale_auth_key   = var.tailscale_auth_key
  cp_allow_scheduling  = [for n in var.nodes_cp : n.allow_scheduling]
  longhorn_enabled     = var.longhorn_enabled
  drain_on_upgrade     = var.drain_on_upgrade
  extra_config_patches = compact(concat(var.extra_config_patches, [local.data_volume_patch]))

  depends_on = [libvirt_domain.node]
}

# Settle after bootstrap
resource "time_sleep" "post_bootstrap" {
  depends_on      = [module.talos_cluster]
  create_duration = "10s"
}

# Health gate: validates on apply, skipped on destroy via enable_health_check=false.
data "talos_cluster_health" "this" {
  count                = var.enable_health_check ? 1 : 0
  depends_on           = [module.talos_cluster, time_sleep.post_bootstrap]
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [for node in var.nodes_cp : node.ip]
  worker_nodes         = [for node in var.nodes_worker : node.ip]
  endpoints            = [for node in var.nodes_cp : node.ip]
  timeouts = {
    read = "10m"
  }
}

