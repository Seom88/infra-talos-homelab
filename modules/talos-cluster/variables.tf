variable "machine_secrets" {
  description = "Talos machine secrets (from talos_machine_secrets resource) — opaque map with certs/keys/secrets"
  type        = any
  nullable    = false
}

variable "client_configuration" {
  description = "Talos client configuration (from talos_machine_secrets resource) — opaque map with CA/certs"
  type        = any
  nullable    = false
}

variable "cp_ips" {
  description = "IP addresses of all control plane nodes"
  type        = list(string)

  validation {
    condition     = length(var.cp_ips) > 0
    error_message = "cp_ips must contain at least one IP."
  }

  validation {
    condition     = alltrue([for ip in var.cp_ips : can(cidrhost("${ip}/32", 0))])
    error_message = "Each cp_ips element must be a valid IPv4 address."
  }
}

variable "cp_hostnames" {
  description = "Hostnames of all control plane nodes (used for certSANs)"
  type        = list(string)

  validation {
    condition     = length(var.cp_hostnames) > 0
    error_message = "cp_hostnames must contain at least one hostname."
  }
}

variable "worker_ips" {
  description = "IP addresses of all worker nodes"
  type        = list(string)

  validation {
    condition     = alltrue([for ip in var.worker_ips : ip == "" || can(cidrhost("${ip}/32", 0))])
    error_message = "Each worker_ips element must be a valid IPv4 address or empty."
  }
}

variable "worker_hostnames" {
  description = "Hostnames of all worker nodes"
  type        = list(string)
}

variable "cluster_name" {
  description = "Name of the Talos/Kubernetes cluster"
  type        = string
  default     = "talos-cluster"

  validation {
    condition     = length(trimspace(var.cluster_name)) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "talos_version" {
  description = "Talos Linux version (e.g. 1.13.3)"
  type        = string

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version must be semver X.Y.Z (e.g. 1.13.9)."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to install (e.g. 1.36.1). Must stay in sync with talos_cluster.kubernetes_version; only used at bootstrap when ignore_kubernetes_upgrade_drift=true (subsequent upgrades via talos_cluster with upgrade-k8s)."
  type        = string
  default     = "1.36.2"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version must be semver X.Y.Z (e.g. 1.36.2)."
  }
}

variable "talos_image_id" {
  description = "Schematic ID from the Talos Image Factory"
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.talos_image_id)) > 0
    error_message = "talos_image_id must not be empty."
  }
}

variable "installer_image" {
  description = <<-EOF
    Installer container image used by talos_machine to keep the node OS version
    in sync (e.g. factory.talos.dev/nocloud-installer/<schematic-id>:v1.13.9).
    Must match the platform flavor of the nodes: roots booting secureboot images
    can omit it (defaults to the nocloud-installer-secureboot built from
    talos_image_id + talos_version); non-secureboot roots (e.g. libvirt) must
    override it or set secureboot=false.
  EOF
  type        = string
  default     = ""
}

variable "secureboot" {
  description = "Whether to use the secureboot installer flavor (factory.talos.dev/nocloud-installer-secureboot). Libvirt (q35 without secureboot) should set false; Proxmox (ovmf) should keep true."
  type        = bool
  default     = true
}

# Tailscale extension disabled - see docs/adr/001-remove-tailscale-extension.md
# To enable: uncomment this variable AND uncomment siderolabs/tailscale in schematic-*.yaml
# variable "tailscale_auth_key" {
#   description = "Tailscale pre-authentication key for node registration. Omit or leave empty to skip Tailscale."
#   type        = string
#   default     = ""
#   sensitive   = true
# }

variable "cp_allow_scheduling" {
  description = "Per control plane node: allow workloads on that node. Index-aligned with cp_hostnames / cp_ips. Each node's machine config gets cluster.allowSchedulingOnControlPlanes: true when its value is true (Talos v1.13 supports per-node machine config)."
  type        = list(bool)
}

variable "longhorn_enabled" {
  description = "Enable Longhorn support: inject kubelet extraMounts for /var/lib/longhorn on all nodes"
  type        = bool
  default     = true
}

variable "extra_config_patches" {
  description = "Additional Talos machine configuration patches (raw YAML strings) applied to all nodes (control plane + workers). UserVolumeConfig patches (e.g. data disk with diskSelector \"!system_disk\" mounted at /var/mnt/<name>) should be passed here; proxmox/libvirt modules auto-append it when any node has data_disk_size."
  type        = list(string)
  default     = []
}
