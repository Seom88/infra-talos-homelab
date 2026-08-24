# ============================================================
# Talos Secrets & Machine Configurations
# ============================================================

resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"
}

locals {
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  installer_path   = var.secureboot ? "nocloud-installer-secureboot" : "nocloud-installer"
  install_image    = "factory.talos.dev/${local.installer_path}/${talos_image_factory_schematic.this.id}:v${var.talos_version}"

  cp_ips                 = [for n in var.nodes_cp : n.ip]
  tailscale_cp_names     = var.tailscale_domain != "" ? [for n in var.nodes_cp : "${n.hostname}.${var.tailscale_domain}"] : []
  tailscale_worker_names = var.tailscale_domain != "" ? [for n in var.nodes_worker : "${n.hostname}.${var.tailscale_domain}"] : []

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

  tailscale_patch = var.tailscale_auth_key != "" ? yamlencode({
    apiVersion = "v1alpha1"
    kind       = "ExtensionServiceConfig"
    name       = "tailscale"
    environment = [
      "TS_AUTHKEY=${var.tailscale_auth_key}",
      "TS_ACCEPT_DNS=false"
    ]
  }) : ""
}

data "talos_machine_configuration" "cp" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = "v${var.kubernetes_version}"
  talos_version      = "v${var.talos_version}"

  config_patches = compact(concat([
    yamlencode({
      machine = {
        certSANs = concat(
          [var.cluster_vip],
          local.cp_ips,
          local.tailscale_cp_names,
        )
        install = {
          disk  = "/dev/vda"
          image = local.install_image
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "Layer2VIPConfig"
      name       = var.cluster_vip
      link       = "eth0"
    }),
    local.tailscale_patch,
    local.longhorn_patch,
  ], var.extra_config_patches))
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = "v${var.kubernetes_version}"
  talos_version      = "v${var.talos_version}"

  config_patches = compact(concat([
    yamlencode({
      machine = {
        certSANs = local.tailscale_worker_names
        install = {
          disk  = "/dev/vda"
          image = local.install_image
        }
      }
    }),
    local.tailscale_patch,
    local.longhorn_patch,
  ], var.extra_config_patches))
}
