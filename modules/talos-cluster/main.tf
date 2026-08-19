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
  tailscale_cp_names     = var.tailscale_domain != "" ? [for hostname in var.cp_hostnames : "${hostname}.${var.tailscale_domain}"] : []
  tailscale_worker_names = var.tailscale_domain != "" ? [for hostname in var.worker_hostnames : "${hostname}.${var.tailscale_domain}"] : []
  all_tailscale_names    = concat(local.tailscale_cp_names, local.tailscale_worker_names)
  cluster_endpoint       = "https://${var.cluster_vip}:6443"
  install_image          = "factory.talos.dev/installer-secureboot/${var.talos_image_id}:v${var.talos_version}"
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

  scheduled_cp_hostnames = [for i, hostname in var.cp_hostnames : hostname if var.cp_allow_scheduling[i]]
}

data "talos_client_configuration" "client_config" {
  cluster_name         = var.cluster_name
  client_configuration = var.client_configuration
  endpoints            = var.cp_ips
  nodes                = local.all_tailscale_names
}

# --- Control Plane Configuration ---

data "talos_machine_configuration" "control_machine_config" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = var.machine_secrets
  kubernetes_version = "v${var.kubernetes_version}"
  talos_version      = "v${var.talos_version}"
  config_patches = compact(concat([
    yamlencode({
      machine = {
        certSANs = concat(local.tailscale_cp_names, var.cp_ips)
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
    var.tailscale_auth_key != "" ? yamlencode({
      apiVersion = "v1alpha1"
      kind       = "ExtensionServiceConfig"
      name       = "tailscale"
      environment = [
        "TS_AUTHKEY=${var.tailscale_auth_key}",
        "TS_ACCEPT_DNS=true"
      ]
    }) : "",
    local.longhorn_patch,
  ], var.extra_config_patches))
}

resource "talos_machine_configuration_apply" "control_machine_config_apply" {
  for_each                    = { for i, hostname in var.cp_hostnames : hostname => var.cp_ips[i] }
  client_configuration        = var.client_configuration
  machine_configuration_input = data.talos_machine_configuration.control_machine_config.machine_configuration
  node                        = each.value
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
        certSANs = local.tailscale_worker_names
        install = {
          disk  = "/dev/vda"
          image = local.install_image
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

resource "talos_machine_configuration_apply" "worker_machine_config_apply" {
  for_each                    = { for i, hostname in var.worker_hostnames : hostname => var.worker_ips[i] }
  client_configuration        = var.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker_machine_config.machine_configuration
  node                        = each.value
}

# --- Bootstrap & Kubeconfig ---

resource "talos_machine_bootstrap" "bootstrap" {
  depends_on           = [talos_machine_configuration_apply.control_machine_config_apply]
  client_configuration = var.client_configuration
  node                 = var.cp_ips[0]
  endpoint             = var.cp_ips[0]
}

resource "talos_cluster_kubeconfig" "kubeconfig" {
  depends_on           = [talos_machine_bootstrap.bootstrap]
  client_configuration = var.client_configuration
  node                 = var.cp_ips[0]
}

# Removes the control-plane taint post-bootstrap for CPs with allow_scheduling=true.
# Per-node taint removal via KubeNodeConfig requires Talos v1.14+; on 1.13 it is
# done imperatively with kubectl once the nodes register with the kube-apiserver.
resource "terraform_data" "remove_control_plane_taints" {
  count = length(local.scheduled_cp_hostnames) > 0 ? 1 : 0

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/remove-control-plane-taints.sh ${join(" ", local.scheduled_cp_hostnames)}"
    environment = {
      KUBECONFIG_CONTENT = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
    }
  }

  depends_on = [talos_cluster_kubeconfig.kubeconfig]
}
