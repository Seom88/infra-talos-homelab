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
  description = "Kubernetes version (e.g. 1.36.3); only at bootstrap, upgrades via talos_cluster."
  type        = string
  default     = "1.36.3"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version must be semver X.Y.Z (e.g. 1.36.3)."
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
  description = "Installer image for talos_machine (e.g. factory.talos.dev/nocloud-installer/<id>:vX.Y.Z). Defaults to secureboot flavor."
  type        = string
  default     = ""
}

variable "secureboot" {
  description = "Use secureboot installer flavor; false for libvirt, true for Proxmox."
  type        = bool
  default     = true
}

# Tailscale disabled - see ADR 001
# To enable: uncomment here and in schematic-*.yaml
# variable "tailscale_auth_key" {
#   description = "Tailscale key; omit to skip."
#   type        = string
#   default     = ""
#   sensitive   = true
# }

variable "cp_allow_scheduling" {
  description = "Per-CP allow scheduling; index-aligned with cp_hostnames/cp_ips."
  type        = list(bool)
}

variable "longhorn_enabled" {
  description = "Enable Longhorn support: inject kubelet extraMounts for /var/lib/longhorn on all nodes"
  type        = bool
  default     = true
}

variable "extra_config_patches" {
  description = "Additional Talos patches (YAML) for all nodes; UserVolumeConfig auto-appended."
  type        = list(string)
  default     = []
}

variable "drain_on_upgrade" {
  description = "Drain before Talos upgrade; keep false in prod with Longhorn."
  type        = bool
  default     = false
}
