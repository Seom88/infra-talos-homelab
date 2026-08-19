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
  depends_on = [
    proxmox_sdn_applier.this
  ]
}

# ── Talos Machine Secrets ────────────────────────
resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"
}

module "talos" {
  source = "../modules/talos-cluster"

  machine_secrets      = talos_machine_secrets.this.machine_secrets
  client_configuration = talos_machine_secrets.this.client_configuration
  cp_ips               = [for node in var.nodes_cp : node.ip]
  cp_hostnames         = [for node in var.nodes_cp : node.hostname]
  worker_ips           = [for node in var.nodes_worker : node.ip]
  worker_hostnames     = [for node in var.nodes_worker : node.hostname]
  cluster_vip          = var.cluster_vip
  talos_version        = var.talos_version
  talos_image_id       = talos_image_factory_schematic.this.id
  tailscale_domain     = var.env_name == "prod" ? var.tailscale_domain : ""
  tailscale_auth_key   = var.env_name == "prod" ? var.tailscale_auth_key : ""
  cp_allow_scheduling  = [for n in var.nodes_cp : n.allow_scheduling]

  depends_on = [
    proxmox_virtual_environment_vm.talos,
    proxmox_virtual_environment_vm.talos_worker
  ]
}

# ── Cluster Health Gate ─────────────────────────
# Blocks apply until kube-apiserver, etcd, and all nodes are Ready,
# so dependent roots (platform/) never race the cluster bootstrap.
data "talos_cluster_health" "this" {
  depends_on           = [module.talos]
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [for node in var.nodes_cp : node.ip]
  worker_nodes         = [for node in var.nodes_worker : node.ip]
  endpoints            = [for node in var.nodes_cp : node.ip]
  timeouts = {
    read = "15m"
  }
}
