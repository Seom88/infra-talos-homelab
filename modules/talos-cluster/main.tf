terraform {
  required_version = ">= 1.11"
  required_providers {
    talos = {
      source = "siderolabs/talos"
      # Pre-release: fixes inconsistent final plan (issue #352); switch to 0.12.0 when stable.
      version = "0.12.0-beta.0"
    }
  }
}

locals {
  cp_names           = var.cp_hostnames
  worker_names       = var.worker_hostnames
  all_nodes_names    = concat(local.cp_names, local.worker_names)
  cluster_endpoint   = "https://${var.cp_ips[0]}:6443"
  base_install_image = var.secureboot ? "factory.talos.dev/nocloud-installer-secureboot/${var.talos_image_id}:v${var.talos_version}" : "factory.talos.dev/nocloud-installer/${var.talos_image_id}:v${var.talos_version}"
  installer_image    = var.installer_image != "" ? var.installer_image : local.base_install_image
  # Multi-disk: UserVolumeConfig "data" -> /var/mnt/data; kubelet bind to /var/lib/longhorn.
  # See https://docs.siderolabs.com/kubernetes-guides/csi/longhorn
  has_data_volume = length([for p in var.extra_config_patches : p if strcontains(p, "UserVolumeConfig")]) > 0
  longhorn_patch = var.longhorn_enabled ? yamlencode({
    machine = {
      kubelet = {
        extraMounts = [
          {
            destination = "/var/lib/longhorn"
            type        = "bind"
            source      = "/var/mnt/data"
            options     = ["bind", "rshared", "rw"]
          }
        ]
      }
    }
  }) : ""

  cp_allow_scheduling_map = { for i, hostname in var.cp_hostnames : hostname => var.cp_allow_scheduling[i] }
  # Per-node scheduling: allowSchedulingOnControlPlanes removes taint per node.
  scheduling_patch = yamlencode({
    cluster = {
      allowSchedulingOnControlPlanes = true
    }
  })
}

# Talos client config for talosctl; TF >=1.11 prefers ephemeral write-only (see below).
data "talos_client_configuration" "client_config" {
  cluster_name         = var.cluster_name
  client_configuration = var.client_configuration
  endpoints            = var.cp_ips
  nodes                = local.all_nodes_names
}

# Control plane config (per-node scheduling patch)
data "talos_machine_configuration" "control_machine_config" {
  for_each         = { for i, hostname in var.cp_hostnames : hostname => var.cp_ips[i] }
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = var.machine_secrets
  talos_version    = "v${var.talos_version}"
  config_patches = compact(concat([
    yamlencode({
      machine = {
        certSANs = concat(local.cp_names, var.cp_ips)
        install = {
          disk  = "/dev/vda"
          image = local.installer_image
        }
      }
    }),
    # Tailscale disabled - see ADR 001
    # var.tailscale_auth_key != "" ? yamlencode({
    #   apiVersion = "v1alpha1"
    #   kind       = "ExtensionServiceConfig"
    #   name       = "tailscale"
    #   environment = [
    #     "TS_AUTHKEY=${var.tailscale_auth_key}",
    #     "TS_ACCEPT_DNS=true"
    #   ]
    # }) : "",
    local.cp_allow_scheduling_map[each.key] ? local.scheduling_patch : "",
    local.longhorn_patch,
  ], var.extra_config_patches))
}

# In-place upgrades via talos_machine.image; bootstrap disk pinned.
resource "talos_machine" "control_plane" {
  for_each              = { for i, hostname in var.cp_hostnames : hostname => var.cp_ips[i] }
  node                  = each.value
  client_configuration  = var.client_configuration
  machine_configuration = data.talos_machine_configuration.control_machine_config[each.key].machine_configuration
  image                 = local.installer_image
  drain_on_upgrade      = var.drain_on_upgrade
  # K8s version owned by talos_cluster; ignore drift for out-of-band upgrades.
  ignore_kubernetes_upgrade_drift = true
}

# Bootstrap

resource "talos_cluster" "cluster" {
  depends_on           = [talos_machine.control_plane]
  node                 = var.cp_ips[0]
  client_configuration = var.client_configuration
  kubernetes_version   = "v${var.kubernetes_version}"
  control_plane_nodes  = var.cp_ips

  timeouts = { create = "15m", update = "30m" }
}

# Worker config
data "talos_machine_configuration" "worker_machine_config" {
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = var.machine_secrets
  talos_version    = "v${var.talos_version}"
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
    # Tailscale disabled - see ADR 001
    # var.tailscale_auth_key != "" ? yamlencode({
    #   apiVersion = "v1alpha1"
    #   kind       = "ExtensionServiceConfig"
    #   name       = "tailscale"
    #   environment = [
    #     "TS_AUTHKEY=${var.tailscale_auth_key}",
    #     "TS_ACCEPT_DNS=false"
    #   ]
    # }) : "",
    local.longhorn_patch,
  ], var.extra_config_patches))
}

resource "talos_machine" "worker" {
  # Workers wait for control plane bootstrap.
  depends_on            = [talos_cluster.cluster]
  for_each              = { for i, hostname in var.worker_hostnames : hostname => var.worker_ips[i] }
  node                  = each.value
  client_configuration  = var.client_configuration
  machine_configuration = data.talos_machine_configuration.worker_machine_config.machine_configuration
  image                 = local.installer_image
  drain_on_upgrade      = var.drain_on_upgrade
  # K8s version owned by talos_cluster.
  ignore_kubernetes_upgrade_drift = true
}

# Live kubeconfig (sensitive, in state); ephemeral is secret-free but local_file
# lacks write-only support (hashicorp/local#373). Switch when available:
# ephemeral "talos_cluster_kubeconfig" "kubeconfig" {
#   cluster_name    = var.cluster_name
#   endpoint        = local.cluster_endpoint
#   machine_secrets = var.machine_secrets
# }
resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_cluster.cluster]
  client_configuration = var.client_configuration
  node                 = var.cp_ips[0]
  endpoint             = var.cp_ips[0]
}
