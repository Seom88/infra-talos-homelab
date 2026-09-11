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
        grow    = true
        minSize = "${local.data_disk_min_gb[name]}GB"
      }
    })
  ]
}

# Canonical Image Factory image (extensions data -> schematic -> URLs); Proxmox always uses the secureboot flavor.
module "image" {
  source        = "../talos-image"
  talos_version = var.talos_version
}

# Bootstrap image only; version bumps use talos_machine.image, not disk recreate.
# DANGER: recreating this wipes etcd.
resource "proxmox_download_file" "talos_image" {
  content_type            = "iso"
  datastore_id            = var.datastore_iso
  node_name               = var.node_name
  url                     = module.image.disk_image_secureboot_url
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
    datastore_id = coalesce(each.value.datastore, var.default_datastore)
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
    datastore_id      = coalesce(each.value.datastore, var.default_datastore)
    type              = "4m"
    pre_enrolled_keys = false
  }
  disk {
    datastore_id = coalesce(each.value.datastore, var.default_datastore)
    file_id      = proxmox_download_file.talos_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = each.value.disk_size
  }
  dynamic "disk" {
    for_each = coalesce(each.value.disks, [])
    content {
      datastore_id = coalesce(disk.value.datastore, var.default_data_datastore, each.value.datastore, var.default_datastore)
      interface    = "virtio${disk.key + 1}"
      iothread     = true
      discard      = "on"
      size         = disk.value.size
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
    datastore_id = coalesce(each.value.datastore, var.default_datastore)
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
    datastore_id      = coalesce(each.value.datastore, var.default_datastore)
    type              = "4m"
    pre_enrolled_keys = false
  }
  disk {
    datastore_id = coalesce(each.value.datastore, var.default_datastore)
    file_id      = proxmox_download_file.talos_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = each.value.disk_size
  }
  dynamic "disk" {
    for_each = coalesce(each.value.disks, [])
    content {
      datastore_id = coalesce(disk.value.datastore, var.default_data_datastore, each.value.datastore, var.default_datastore)
      interface    = "virtio${disk.key + 1}"
      iothread     = true
      discard      = "on"
      size         = disk.value.size
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
  installer_image      = module.image.installer_image_secureboot
  # Tailscale disabled - see ADR 001
  # tailscale_auth_key   = var.tailscale_auth_key
  cp_allow_scheduling  = [for n in var.nodes_cp : n.allow_scheduling]
  longhorn_enabled     = var.longhorn_enabled
  drain_on_upgrade     = var.drain_on_upgrade
  extra_config_patches = compact(concat(var.extra_config_patches, local.data_volume_patches))

  depends_on = [
    proxmox_virtual_environment_vm.talos,
    proxmox_virtual_environment_vm.talos_worker
  ]
}

# API-ready gate before K8s consumers (kubeconfig -> platform).
# Talos-layer only (no K8s Ready checks), safe before Cilium CNI is installed.
# Post-CNI node readiness stays in platform wait_nodes (kubectl wait Ready).
data "talos_cluster_health" "this" {
  count                = var.enable_health_check ? 1 : 0
  depends_on           = [module.talos]
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [for node in var.nodes_cp : node.ip]
  worker_nodes         = [for node in var.nodes_worker : node.ip]
  endpoints            = [for node in var.nodes_cp : node.ip]

  skip_kubernetes_checks = true

  timeouts = {
    read = "10m"
  }
}

