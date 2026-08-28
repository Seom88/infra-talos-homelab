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

# ── Talos Schematic ──────────────────────────────
resource "talos_image_factory_schematic" "this" {
  schematic = file(var.schematic_path)
}

# ── Proxmox Image ────────────────────────────────
# Bootstrap image only: pins the disk the VMs are FIRST created from.
# Bumping var.talos_version does NOT recreate this file (see lifecycle below) —
# that would wipe etcd per README "Changes that destroy your cluster". In-place
# upgrades are handled by talos_machine.image (installer), not by recreating
# disks. Only a fresh `terraform destroy` + `apply`, or manually tainting
# this resource, pulls a new bootstrap image.
resource "proxmox_download_file" "talos_image" {
  content_type            = "iso"
  datastore_id            = var.datastore_iso
  node_name               = var.node_name
  url                     = "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/v${var.talos_version}/nocloud-amd64-secureboot.raw.xz"
  decompression_algorithm = "zst"
  file_name               = "talos-nocloud-amd64-secureboot.img"
  overwrite               = false
  overwrite_unmanaged     = true

  lifecycle {
    ignore_changes = [url]
  }
}

resource "proxmox_virtual_environment_vm" "talos" {
  started         = true
  on_boot         = true
  stop_on_destroy = true
  tags            = ["terraform", "talos", "control-plane"]
  for_each        = { for node in var.nodes_cp : node.hostname => node }
  name            = each.key
  node_name       = each.value.proxmox_node
  bios            = "ovmf"
  machine         = "q35"
  initialization {
    datastore_id = each.value.datastore
    ip_config {
      ipv4 {
        address = "${each.value.ip}/${split("/", var.network_cidr)[1]}"
        gateway = var.gateway
      }
    }
  }
  agent {
    enabled = true
  }
  efi_disk {
    datastore_id      = each.value.datastore
    type              = "4m"
    pre_enrolled_keys = false
  }
  disk {
    datastore_id = each.value.datastore
    file_id      = proxmox_download_file.talos_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = each.value.disk_size
  }
  dynamic "disk" {
    for_each = try(each.value.data_disk_size, null) != null ? [1] : []
    content {
      datastore_id = coalesce(try(each.value.data_datastore, null), each.value.datastore)
      interface    = "virtio1"
      iothread     = true
      discard      = "on"
      size         = each.value.data_disk_size
    }
  }
  cpu {
    cores = each.value.cores
    type  = "host"
  }
  memory {
    dedicated = each.value.memory
    floating  = each.value.memory
  }
  network_device {
    bridge   = var.network_bridge
    firewall = false
  }
  operating_system {
    type = "l26"
  }
  depends_on = [
    proxmox_sdn_applier.this
  ]
}

resource "proxmox_virtual_environment_vm" "talos_worker" {
  started         = true
  on_boot         = true
  stop_on_destroy = true
  tags            = ["terraform", "talos", "worker"]
  for_each        = { for node in var.nodes_worker : node.hostname => node }
  name            = each.key
  node_name       = each.value.proxmox_node
  bios            = "ovmf"
  machine         = "q35"
  initialization {
    datastore_id = each.value.datastore
    ip_config {
      ipv4 {
        address = "${each.value.ip}/${split("/", var.network_cidr)[1]}"
        gateway = var.gateway
      }
    }
  }
  agent {
    enabled = true
  }
  efi_disk {
    datastore_id      = each.value.datastore
    type              = "4m"
    pre_enrolled_keys = false
  }
  disk {
    datastore_id = each.value.datastore
    file_id      = proxmox_download_file.talos_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = each.value.disk_size
  }
  dynamic "disk" {
    for_each = try(each.value.data_disk_size, null) != null ? [1] : []
    content {
      datastore_id = coalesce(try(each.value.data_datastore, null), each.value.datastore)
      interface    = "virtio1"
      iothread     = true
      discard      = "on"
      size         = each.value.data_disk_size
    }
  }
  cpu {
    cores = each.value.cores
    type  = "host"
  }
  memory {
    dedicated = each.value.memory
    floating  = each.value.memory
  }
  network_device {
    bridge   = var.network_bridge
    firewall = false
  }
  operating_system {
    type = "l26"
  }
  depends_on = [
    proxmox_sdn_applier.this
  ]
}

# ── Talos Machine Secrets ────────────────────────
resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"

  # Secrets are bootstrap-only: version bumps must not rotate the CA. In-place upgrades are handled by talos_machine.image (installer) in talos-cluster module.
  lifecycle {
    ignore_changes = [talos_version]
  }
}

module "talos" {
  source = "../talos-cluster"

  machine_secrets      = talos_machine_secrets.this.machine_secrets
  client_configuration = talos_machine_secrets.this.client_configuration
  cp_ips               = [for node in var.nodes_cp : node.ip]
  cp_hostnames         = [for node in var.nodes_cp : node.hostname]
  worker_ips           = [for node in var.nodes_worker : node.ip]
  worker_hostnames     = [for node in var.nodes_worker : node.hostname]
  talos_version        = var.talos_version
  talos_image_id       = talos_image_factory_schematic.this.id
  # tailscale disabled - see docs/adr/001-remove-tailscale-extension.md
  # tailscale_auth_key   = var.tailscale_auth_key
  cp_allow_scheduling  = [for n in var.nodes_cp : n.allow_scheduling]
  longhorn_enabled     = var.longhorn_enabled
  extra_config_patches = compact(concat(var.extra_config_patches, [local.data_volume_patch]))

  depends_on = [
    proxmox_virtual_environment_vm.talos,
    proxmox_virtual_environment_vm.talos_worker
  ]
}

# ── Bootstrap settle wait ───────────────────────
resource "time_sleep" "post_bootstrap" {
  depends_on      = [module.talos]
  create_duration = "10s" # C: was 45s, reduced - health retry handles etcd Preparing; if flakes persist, restore 30s
}

# ── Cluster Health Gate (data + check: validates but does NOT block destroy) ─
# `enable_health_check` lets `just tf-destroy` skip the gate (TF_VAR_enable_health_check=false).
# On apply (default true) the data source waits 10m for K8s Ready (B+C: talos_cluster is
# single-node fast, health now handles full HA wait); on destroy it has count=0
# so `terraform destroy` doesn't hang even when you want to start from zero.
data "talos_cluster_health" "this" {
  count                = var.enable_health_check ? 1 : 0
  depends_on           = [module.talos, time_sleep.post_bootstrap]
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [for node in var.nodes_cp : node.ip]
  worker_nodes         = [for node in var.nodes_worker : node.ip]
  endpoints            = [for node in var.nodes_cp : node.ip]
  timeouts = {
    read = "10m"
  }
}

