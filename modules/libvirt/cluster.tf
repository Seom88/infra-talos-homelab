locals {
  has_data_disk = length([for n in concat(var.nodes_cp, var.nodes_worker) : n if try(n.data_disk_size, null) != null]) > 0
  # UserVolumeConfig intentionally named "data" -> /var/mnt/data (generic, not workload-specific).
  # Sidero official Longhorn example uses name="longhorn" -> /var/mnt/longhorn with grow:false and
  # diskSelector `disk.transport == 'nvme' && !system_disk`. We use name="data" for flexibility
  # (other workloads can reuse it) — set Helm `defaultSettings.defaultDataPath=/var/mnt/data`
  # accordingly (would be /var/mnt/longhorn if you follow Sidero's name verbatim).
  # virtio disks: "!system_disk" alone is sufficient; nvme filter only applies to bare-metal NVMe.
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
  # tailscale disabled - see docs/adr/001-remove-tailscale-extension.md
  # tailscale_auth_key   = var.tailscale_auth_key
  cp_allow_scheduling  = [for n in var.nodes_cp : n.allow_scheduling]
  longhorn_enabled     = var.longhorn_enabled
  extra_config_patches = compact(concat(var.extra_config_patches, [local.data_volume_patch]))

  depends_on = [libvirt_domain.node]
}

# ── Bootstrap settle wait ───────────────────────
resource "time_sleep" "post_bootstrap" {
  depends_on      = [module.talos_cluster]
  create_duration = "10s" # C: was 45s, reduced - health retry handles etcd Preparing; if flakes persist, restore 30s
}

# ── Cluster Health Gate (data + check: validates but does NOT block destroy) ─
# `enable_health_check` lets `just tf-destroy` skip the gate (TF_VAR_enable_health_check=false).
# On apply (default true) the data source waits 10m for K8s Ready (B+C: talos_cluster is
# single-node fast, health now handles full HA wait); on destroy it has count=0
# so `terraform destroy` doesn't hang even when you want to start from zero.
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

