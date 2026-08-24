terraform {
  required_providers {
    talos = {
      source = "siderolabs/talos"
      # TODO: using alpha to fix "inconsistent final plan" bug (siderolabs/terraform-provider-talos#352).
      # Revert to stable when v0.12.0 is released.
      version = "0.12.0-alpha.5"
    }
  }
}

locals {
  cp_names         = var.tailscale_domain != "" ? [for hostname in var.cp_hostnames : "${hostname}.${var.tailscale_domain}"] : []
  worker_names     = var.tailscale_domain != "" ? [for hostname in var.worker_hostnames : "${hostname}.${var.tailscale_domain}"] : []
  all_nodes_names  = concat(local.cp_names, local.worker_names)
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  base_install_image = var.secureboot ? "factory.talos.dev/nocloud-installer-secureboot/${var.talos_image_id}:v${var.talos_version}" : "factory.talos.dev/nocloud-installer/${var.talos_image_id}:v${var.talos_version}"
  installer_image = var.installer_image != "" ? var.installer_image : local.base_install_image
  longhorn_patch = var.longhorn_enabled ? yamlencode({
    machine = {
      kubelet = {
        extraMounts = [
          {
            destination = "/var/lib/longhorn"
            type        = "bind"
            source      = "/var/lib/longhorn"
            options     = ["bind", "rshared", "rw"]
          }
        ]
      }
    }
  }) : ""

  cp_allow_scheduling_map = { for i, hostname in var.cp_hostnames : hostname => var.cp_allow_scheduling[i] }
  # Durable per Sidero docs (Talos v1.13): cluster.allowSchedulingOnControlPlanes makes
  # the kubelet itself skip the control-plane taint. Applied PER NODE: each control plane
  # node gets its own machine config, so only nodes with allow_scheduling=true lose the
  # taint. Replaces the fragile post-bootstrap `kubectl taint` removal, which the kubelet
  # re-applies on restart.
  scheduling_patch = yamlencode({
    cluster = {
      allowSchedulingOnControlPlanes = true
    }
  })
}

data "talos_client_configuration" "client_config" {
  cluster_name         = var.cluster_name
  client_configuration = var.client_configuration
  endpoints            = var.cp_ips
  nodes                = local.all_nodes_names
}

# --- Control Plane Configuration (per node: scheduling patch is node-specific) ---

data "talos_machine_configuration" "control_machine_config" {
  for_each           = { for i, hostname in var.cp_hostnames : hostname => var.cp_ips[i] }
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = var.machine_secrets
  kubernetes_version = "v${var.kubernetes_version}"
  talos_version      = "v${var.talos_version}"
  config_patches = compact(concat([
    yamlencode({
      machine = {
        certSANs = concat([var.cluster_vip], local.cp_names, var.cp_ips)
        install = {
          disk  = "/dev/vda"
          image = local.installer_image
        }
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
        "TS_ACCEPT_DNS=true"
      ]
    }) : "",
    local.cp_allow_scheduling_map[each.key] ? local.scheduling_patch : "",
    local.longhorn_patch,
  ], var.extra_config_patches))
}

# IaC version management: talos_machine applies config AND keeps the OS
# version in sync via `image`. Bumping var.talos_version triggers an
# in-place upgrade (pull → install → reboot) without recreating VMs — the
# download_file has `ignore_changes = [url]` so the bootstrap disk stays.
# Drain is off (workloads on CPs, no workers yet); revisit when workers exist.

resource "talos_machine" "control_plane" {
  for_each              = { for i, hostname in var.cp_hostnames : hostname => var.cp_ips[i] }
  node                  = each.value
  client_configuration  = var.client_configuration
  machine_configuration = data.talos_machine_configuration.control_machine_config[each.key].machine_configuration
  image                 = local.installer_image
  drain_on_upgrade      = false
}

# --- Worker Configuration ---

data "talos_machine_configuration" "worker_machine_config" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = var.machine_secrets
  kubernetes_version = "v${var.kubernetes_version}"
  talos_version      = "v${var.talos_version}"
  config_patches = compact(concat([
    yamlencode({
      machine = {
        certSANs = local.worker_names
        install = {
          disk  = "/dev/vda"
          image = local.installer_image
        }
      }
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
    local.longhorn_patch,
  ], var.extra_config_patches))
}

resource "talos_machine" "worker" {
  for_each              = { for i, hostname in var.worker_hostnames : hostname => var.worker_ips[i] }
  node                  = each.value
  client_configuration  = var.client_configuration
  machine_configuration = data.talos_machine_configuration.worker_machine_config.machine_configuration
  image                 = local.installer_image
  drain_on_upgrade      = false
}

# --- Bootstrap & Kubeconfig ---

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine.control_plane]
  client_configuration = var.client_configuration
  node                 = var.cp_ips[0]
  endpoint             = var.cp_ips[0]
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap]
  client_configuration = var.client_configuration
  node                 = var.cp_ips[0]
}
