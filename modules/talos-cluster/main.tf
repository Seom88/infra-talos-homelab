terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
}

locals {
  tailscale_names  = var.tailscale_domain != "" ? [for hostname in var.node_hostnames : "${hostname}.${var.tailscale_domain}"] : []
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  install_image    = "factory.talos.dev/installer/${var.talos_image_id}:v${var.talos_version}"
}

resource "talos_machine_secrets" "machine_secrets" {
  talos_version = "v${var.talos_version}"
}

data "talos_client_configuration" "client_config" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  endpoints            = var.node_ips
  nodes                = local.tailscale_names
}

data "talos_machine_configuration" "control_machine_config" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.machine_secrets.machine_secrets
  kubernetes_version = "v${var.kubernetes_version}"
  talos_version      = "v${var.talos_version}"
  config_patches = compact([
    yamlencode({
      machine = {
        certSANs = concat(local.tailscale_names, var.node_ips)
        install = {
          disk  = "/dev/vda"
          image = local.install_image
        }
      }
    }),
    yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "Layer2VIPConfig"
      name       = var.cluster_vip
      link       = "eth0"
    }),
    var.tailscale_auth_key != "" ? yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "tailscale"
      environment = [
        "TS_AUTHKEY=${var.tailscale_auth_key}",
        "TS_ACCEPT_DNS=false"
      ]
    }) : "",
  ])
}

resource "talos_machine_configuration_apply" "control_machine_config_apply" {
  for_each                    = { for i, hostname in var.node_hostnames : hostname => var.node_ips[i] }
  client_configuration        = talos_machine_secrets.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_machine_config.machine_configuration
  node                        = each.value
}

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.control_machine_config_apply]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = var.node_ips[0]
  endpoint             = var.node_ips[0]
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap]
  client_configuration = talos_machine_secrets.machine_secrets.client_configuration
  node                 = var.node_ips[0]
}
