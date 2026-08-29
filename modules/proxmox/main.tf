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

# Talos schematic
resource "talos_image_factory_schematic" "this" {
  schematic = file(var.schematic_path)
}

# Bootstrap image only; version bumps use talos_machine.image, not disk recreate.
# DANGER: recreating this wipes etcd.
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

# Talos machine secrets (bootstrap-only)
resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"

  # Bootstrap-only: version bumps must not rotate CA.
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
  # Tailscale disabled - see ADR 001
  # tailscale_auth_key   = var.tailscale_auth_key
  cp_allow_scheduling  = [for n in var.nodes_cp : n.allow_scheduling]
  longhorn_enabled     = var.longhorn_enabled
  drain_on_upgrade     = var.drain_on_upgrade
  extra_config_patches = compact(concat(var.extra_config_patches, [local.data_volume_patch]))

  depends_on = [
    proxmox_virtual_environment_vm.talos,
    proxmox_virtual_environment_vm.talos_worker
  ]
}

# Settle after bootstrap
resource "time_sleep" "post_bootstrap" {
  depends_on      = [module.talos]
  create_duration = "10s"
}

# Health gate: validates on apply, skipped on destroy via enable_health_check=false.
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

