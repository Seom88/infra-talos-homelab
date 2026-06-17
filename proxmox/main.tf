resource "proxmox_download_file" "talos_image" {
  content_type            = "iso"
  datastore_id            = var.datastore_iso
  node_name               = var.node_name
  url                     = "https://factory.talos.dev/image/${var.talos_image_factory_id}/v${var.talos_version}/nocloud-amd64.raw.xz"
  decompression_algorithm = "zst"
  file_name               = "talos-${var.env_name}-v${var.talos_version}-nocloud-amd64.img"
  overwrite               = false
}

resource "proxmox_virtual_environment_vm" "talos" {
  on_boot         = true
  stop_on_destroy = true
  tags            = ["terraform", "talos", "control-plane"]
  for_each        = { for node in var.nodes_cp : node.hostname => node }
  name            = each.key
  node_name       = each.value.proxmox_node
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
  disk {
    datastore_id = var.datastore_vm
    file_id      = proxmox_download_file.talos_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 20
  }
  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
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
  on_boot         = true
  stop_on_destroy = true
  tags            = ["terraform", "talos", "worker"]
  for_each        = { for node in var.nodes_worker : node.hostname => node }
  name            = each.key
  node_name       = each.value.proxmox_node
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
  disk {
    datastore_id = var.datastore_vm
    file_id      = proxmox_download_file.talos_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 100
  }
  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
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

locals {
  tailscale_domain = "lonk-mirfak.ts.net"
}

module "talos" {
  source = "../modules/talos-cluster"

  cp_ips           = [for node in var.nodes_cp : node.ip]
  cp_hostnames     = [for node in var.nodes_cp : node.hostname]
  worker_ips       = [for node in var.nodes_worker : node.ip]
  worker_hostnames = [for node in var.nodes_worker : node.hostname]
  cluster_vip        = var.cluster_vip
  talos_version      = var.talos_version
  talos_image_id     = var.talos_image_factory_id
  tailscale_domain   = local.tailscale_domain
  tailscale_auth_key = var.tailscale_auth_key

  depends_on = [
    proxmox_virtual_environment_vm.talos,
    proxmox_virtual_environment_vm.talos_worker
  ]
}
