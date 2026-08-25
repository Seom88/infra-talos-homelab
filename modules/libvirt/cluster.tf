locals {
  has_data_disk = length([for n in concat(var.nodes_cp, var.nodes_worker) : n if try(n.data_disk_size, null) != null]) > 0
  data_volume_patch = local.has_data_disk ? yamlencode({
    apiVersion = "v1alpha1"
    kind       = "UserVolumeConfig"
    name       = "data"
    provisioning = {
      diskSelector = { match = "!system_disk" }
    }
  }) : ""
}

# ============================================================
# Talos Machine Secrets
# ============================================================

resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"

  # Secrets are bootstrap-only: version bumps must not rotate the CA. In-place upgrades are handled by talos_machine.image (installer) in talos-cluster module.
  lifecycle {
    ignore_changes = [talos_version]
  }
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
  tailscale_auth_key   = var.tailscale_auth_key
  cp_allow_scheduling  = [for n in var.nodes_cp : n.allow_scheduling]
  longhorn_enabled     = var.longhorn_enabled
  extra_config_patches = compact(concat(var.extra_config_patches, [local.data_volume_patch]))

  depends_on = [libvirt_domain.node]
}

# ── Bootstrap settle wait ───────────────────────
# 45s is enough for etcd learner promotion + static pods, keeps disposable fast
# (was 90s, too slow). Without this, data.talos_cluster_health can pass with
# cp1 Ready but cp2/cp3 still SCHEDULER Unhealthy (disposable clusters).
resource "time_sleep" "post_bootstrap" {
  depends_on      = [module.talos_cluster]
  create_duration = "45s"
}

# ── Cluster Health Gate ─────────────────────────
# Blocks apply until kube-apiserver, etcd, and all nodes are Ready,
# so dependent roots (platform/) never race the cluster bootstrap.
data "talos_cluster_health" "this" {
  depends_on           = [module.talos_cluster, time_sleep.post_bootstrap]
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [for node in var.nodes_cp : node.ip]
  worker_nodes         = [for node in var.nodes_worker : node.ip]
  endpoints            = [for node in var.nodes_cp : node.ip]
  timeouts = {
    read = "20m"
  }
}
