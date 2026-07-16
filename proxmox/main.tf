# ── Talos Schematic ──────────────────────────────
resource "talos_image_factory_schematic" "this" {
  schematic = file("${path.module}/../schematic-${var.env_name}.yaml")
}

# ── Proxmox Image ────────────────────────────────
resource "proxmox_download_file" "talos_image" {
  content_type            = "iso"
  datastore_id            = var.datastore_iso
  node_name               = var.node_name
  url                     = "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/v${var.talos_version}/nocloud-amd64-secureboot.raw.xz"
  decompression_algorithm = "zst"
  file_name               = "talos-${var.env_name}-v${var.talos_version}-nocloud-amd64-secureboot.img"
  overwrite               = false
  overwrite_unmanaged     = true
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
    datastore_id = var.datastore_vm
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.gateway
      }
    }
  }
  agent {
    enabled = true
  }
  efi_disk {
    datastore_id      = var.datastore_vm
    type              = "4m"
    pre_enrolled_keys = false
  }
  disk {
    datastore_id = var.datastore_vm
    file_id      = proxmox_download_file.talos_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.disk_size_cp
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
    bridge = var.network_bridge
  }
  operating_system {
    type = "l26"
  }
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
    datastore_id = var.datastore_vm
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.gateway
      }
    }
  }
  agent {
    enabled = true
  }
  efi_disk {
    datastore_id      = var.datastore_vm
    type              = "4m"
    pre_enrolled_keys = false
  }
  disk {
    datastore_id = var.datastore_vm
    file_id      = proxmox_download_file.talos_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.disk_size_worker
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
    bridge = var.network_bridge
  }
  operating_system {
    type = "l26"
  }
}

# ── Talos Machine Secrets ────────────────────────
resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"
}

module "talos" {
  source = "../modules/talos-cluster"

  machine_secrets                    = talos_machine_secrets.this.machine_secrets
  client_configuration               = talos_machine_secrets.this.client_configuration
  cp_ips                             = [for node in var.nodes_cp : node.ip]
  cp_hostnames                       = [for node in var.nodes_cp : node.hostname]
  worker_ips                         = [for node in var.nodes_worker : node.ip]
  worker_hostnames                   = [for node in var.nodes_worker : node.hostname]
  cluster_vip                        = var.cluster_vip
  talos_version                      = var.talos_version
  talos_image_id                     = talos_image_factory_schematic.this.id
  tailscale_domain                   = var.env_name == "prod" ? var.tailscale_domain : ""
  tailscale_auth_key                 = var.env_name == "prod" ? var.tailscale_auth_key : ""
  allow_scheduling_on_control_planes = var.allow_scheduling_on_control_planes

  depends_on = [
    proxmox_virtual_environment_vm.talos,
    proxmox_virtual_environment_vm.talos_worker
  ]
}
