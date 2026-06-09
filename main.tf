resource "proxmox_download_file" "talos_image" {
  content_type            = "iso"
  datastore_id            = var.datastore_iso
  node_name               = var.node_name
  url                     = "https://factory.talos.dev/image/${var.talos_image_factory_id}/v${var.talos_version}/nocloud-amd64.raw.xz"
  decompression_algorithm = "zst"
  file_name               = "talos-v${var.talos_version}-nocloud-amd64.img"
  overwrite               = false
}

resource "proxmox_virtual_environment_vm" "talos" {
  on_boot         = true
  stop_on_destroy = true
  tags            = ["terraform", "talos"]
  for_each        = { for node in var.nodes : node.hostname => node }
  name            = each.key
  node_name = each.value.proxmox_node
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
    bridge = "vmbr0"
  }
  operating_system {
    type = "l26"
  }
}

resource "talos_machine_secrets" "machine_secrets" {
  talos_version = "v${var.talos_version}"
}

data "talos_client_configuration" "client_config" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = local.node_ips
  nodes                = local.node_ips
}

locals {
  node_ips = [for node in var.nodes : node.ip]
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  install_image = "factory.talos.dev/installer/${var.talos_image_factory_id}:v${var.talos_version}"
}

data "talos_machine_configuration" "control_machine_config" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = "v${var.kubernetes_version}"
  talos_version      = "v${var.talos_version}"
  config_patches = [
    yamlencode({
      machine = {
        # Configure the installation disk and image for the Talos installer
        install = {
          disk  = "/dev/vda"
          image = local.install_image
        }
        # Dns
        network = {
          nameservers = [var.gateway, "1.1.1.1"]
        }
      }
    }),
    # Enable workers on your control plane nodes
    yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
    }),
    # Layer2VIPConfig
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "Layer2VIPConfig"
      name       = var.cluster_vip
      link       = "eth0"
    }),
    # tailscale
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "tailscale"
      environment = [
        "TS_AUTHKEY=${var.tailscale_auth_key}",
        "TS_ACCEPT_DNS=false"
      ]
    }),
  ]
}

resource "talos_machine_configuration_apply" "control_machine_config_apply" {
  for_each                    = { for node in var.nodes : node.hostname => node }
  depends_on                  = [proxmox_virtual_environment_vm.talos]
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_machine_config.machine_configuration
  node                        = each.value.ip
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.control_machine_config_apply]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.node_ips[0]
  endpoint             = local.node_ips[0]
}

# Generating config files
resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = local.node_ips[0]
}
