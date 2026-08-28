terraform {
  required_providers {
    talos = {
      source = "siderolabs/talos"
      # Pre-release 0.12.0-alpha.5: latest pre-release fixing "inconsistent final plan" bug (siderolabs/terraform-provider-talos#352).
      # Successor is stable 0.12.0 (not yet released) — switch to "0.12.0" when available.
      version = "0.12.0-alpha.5"
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
  # SideroLabs multi-disk recommendation: Disk1 = system (EFI/META/STATE/EPHEMERAL),
  # Disk2 = user volumes via UserVolumeConfig diskSelector "!system_disk" mounted at /var/mnt/<name>.
  # We intentionally use UserVolumeConfig name="data" -> /var/mnt/data (generic, reusable) instead of
  # Sidero's official Longhorn example name="longhorn" -> /var/mnt/longhorn (grow:false,
  # diskSelector `disk.transport == 'nvme' && !system_disk`). Prod is already provisioned as
  # u-data on /dev/vdb1 at /var/mnt/data (verified via talosctl); renaming to "longhorn" would
  # orphan the volume, so the name stays "data".
  # Longhorn Helm must be: --set defaultSettings.defaultDataPath=/var/mnt/data
  # (would be /var/mnt/longhorn if you follow Sidero's name verbatim — see modules/*/ UserVolumeConfig).
  # The kubelet extraMount below keeps /var/lib/longhorn bind-mounted (Sidero privileged requirement:
  # kubelet needs rshared bind at /var/lib/longhorn) for both single-disk (backward compat) and
  # dual-disk setups — Longhorn is pointed at /var/mnt/data via Helm without changing this mount.
  # Direct-mount variant if desired: source = "/var/mnt/data" + update Helm defaultDataPath.
  has_data_volume = length([for p in var.extra_config_patches : p if strcontains(p, "UserVolumeConfig")]) > 0
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

# Talos client configuration derived from machine secrets — used for talosctl.
# Note: Terraform >=1.11 best practice is to avoid persisting secrets in state via
# ephemeral resources + write-only arguments (client_configuration_wo / machine_configuration_wo).
# See commented ephemeral "talos_cluster_kubeconfig" example below and
# https://registry.terraform.io/providers/siderolabs/talos/latest/docs#write-only-arguments
data "talos_client_configuration" "client_config" {
  cluster_name         = var.cluster_name
  client_configuration = var.client_configuration
  endpoints            = var.cp_ips
  nodes                = local.all_nodes_names
}

# --- Control Plane Configuration (per node: scheduling patch is node-specific) ---

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
    # Tailscale ExtensionServiceConfig disabled - uncomment together with variable and schematic
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
  drain_on_upgrade      = var.drain_on_upgrade
  # When used with talos_cluster, Kubernetes upgrades are driven by
  # talos_cluster.kubernetes_version (via upgrade-k8s). Ignore drift so
  # out-of-band k8s upgrades don't force config re-apply.
  # https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine#ignore_kubernetes_upgrade_drift
  ignore_kubernetes_upgrade_drift = true
}

# --- Bootstrap (replaces talos_machine_bootstrap) ---

resource "talos_cluster" "cluster" {
  depends_on           = [talos_machine.control_plane]
  node                 = var.cp_ips[0]
  client_configuration = var.client_configuration
  kubernetes_version   = "v${var.kubernetes_version}"
  control_plane_nodes  = var.cp_ips

  timeouts = { create = "15m", update = "30m" }
}

# --- Worker Configuration ---

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
    # Tailscale ExtensionServiceConfig disabled - uncomment together with variable and schematic
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
  # Workers must wait for the control plane to be bootstrapped before applying
  # their config. Without this, workers attempt to reach the API server before
  # etcd is up, resulting in connection refused errors.
  depends_on            = [talos_cluster.cluster]
  for_each              = { for i, hostname in var.worker_hostnames : hostname => var.worker_ips[i] }
  node                  = each.value
  client_configuration  = var.client_configuration
  machine_configuration = data.talos_machine_configuration.worker_machine_config.machine_configuration
  image                 = local.installer_image
  drain_on_upgrade      = var.drain_on_upgrade
  # See control_plane comment: Kubernetes version is owned by talos_cluster.
  # https://registry.terraform.io/providers/siderolabs/talos/latest/docs/resources/machine#ignore_kubernetes_upgrade_drift
  ignore_kubernetes_upgrade_drift = true
}

# Live retrieval (provider-recommended replacement for deprecated data source).
# Stores kubeconfig in state (sensitive) but validates against live API.
# Ephemeral offline generation (from machine_secrets) is the secret-free ideal on TF >= 1.11,
# but local_file/local_sensitive_file don't yet support write-only (hashicorp/local#373),
# so the ephemeral value can't be written to disk without hitting "Ephemeral value not allowed".
# Keep this resource until local provider supports write-only; then switch to:
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
