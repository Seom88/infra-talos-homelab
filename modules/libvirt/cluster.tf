locals {
  # One UserVolumeConfig per distinct disks[].name across CP + workers.
  # Single name ("data") => single UVC /var/mnt/data (previous behavior).
  # by-id is unknown at plan-time (Talos populates disk IDs post-boot), so the
  # multi-disk selector is best-effort: !system_disk + per-name size floor.
  # Harden post-bootstrap with `talosctl get disks -o yaml` and pin
  # diskSelector.match to by-id/serial when two names share the same size.
  all_data_disks   = flatten([for n in concat(var.nodes_cp, var.nodes_worker) : coalesce(n.disks, [])])
  data_disk_names  = distinct([for d in local.all_data_disks : d.name])
  data_disk_min_gb = { for name in local.data_disk_names : name => min([for d in local.all_data_disks : d.size if d.name == name]...) }
  data_volume_patches = [
    for name in local.data_disk_names : yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = name
      provisioning = {
        diskSelector = {
          match = length(local.data_disk_names) == 1 ? "!system_disk" : "!system_disk && disk.size >= ${local.data_disk_min_gb[name] * 1073741824}u"
        }
        grow    = false
        minSize = "${local.data_disk_min_gb[name]}GB"
      }
    })
  ]
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
  installer_image      = var.secureboot ? module.image.installer_image_secureboot : module.image.installer_image
  # Tailscale disabled - see ADR 001
  # tailscale_auth_key   = var.tailscale_auth_key
  cp_allow_scheduling  = [for n in var.nodes_cp : n.allow_scheduling]
  longhorn_enabled     = var.longhorn_enabled
  drain_on_upgrade     = var.drain_on_upgrade
  extra_config_patches = compact(concat(var.extra_config_patches, local.data_volume_patches))

  depends_on = [libvirt_domain.node]
}

# API-ready gate before K8s consumers (kubeconfig -> platform).
# Talos-layer only (no K8s Ready checks), safe before Cilium CNI is installed.
# Post-CNI node readiness stays in platform wait_nodes (kubectl wait Ready).
data "talos_cluster_health" "this" {
  count                = var.enable_health_check ? 1 : 0
  depends_on           = [module.talos_cluster]
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [for node in var.nodes_cp : node.ip]
  worker_nodes         = [for node in var.nodes_worker : node.ip]
  endpoints            = [for node in var.nodes_cp : node.ip]

  skip_kubernetes_checks = true

  timeouts = {
    read = "10m"
  }
}

