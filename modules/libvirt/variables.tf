# Nodes

variable "nodes_cp" {
  description = "Control plane nodes; optional data_disk_size creates vdb -> /var/mnt/data."
  type = list(object({
    hostname         = string
    ip               = string
    mac              = optional(string)
    cores            = number
    memory           = number
    disk_size        = number
    pool             = optional(string)
    allow_scheduling = bool
    data_disk_size   = optional(number)
    data_pool        = optional(string)
  }))

  validation {
    condition     = alltrue([for n in var.nodes_cp : n.disk_size > 0])
    error_message = "disk_size must be >0"
  }

  validation {
    condition = alltrue([
      for n in var.nodes_cp : (
        try(n.data_pool, null) != null ? try(n.data_disk_size, null) != null : true
        ) && (
        try(n.data_disk_size, null) == null ? true : try(n.data_disk_size, 0) > 0
      )
    ])
    error_message = "data_disk_size must be >0 when set; data_datastore/data_pool requires data_disk_size"
  }
}

variable "nodes_worker" {
  description = "Worker nodes; optional data_disk_size creates vdb -> /var/mnt/data."
  type = list(object({
    hostname       = string
    ip             = string
    mac            = optional(string)
    cores          = number
    memory         = number
    disk_size      = number
    pool           = optional(string)
    data_disk_size = optional(number)
    data_pool      = optional(string)
  }))

  validation {
    condition     = alltrue([for n in var.nodes_worker : n.disk_size > 0])
    error_message = "disk_size must be >0"
  }

  validation {
    condition = alltrue([
      for n in var.nodes_worker : (
        try(n.data_pool, null) != null ? try(n.data_disk_size, null) != null : true
        ) && (
        try(n.data_disk_size, null) == null ? true : try(n.data_disk_size, 0) > 0
      )
    ])
    error_message = "data_disk_size must be >0 when set; data_datastore/data_pool requires data_disk_size"
  }
}

# Storage pool

variable "pool_name" {
  description = "Name of the dedicated storage pool for Talos"
  type        = string
  default     = "talos-pool"
}

variable "pool_path" {
  description = "Target directory for the Talos storage pool"
  type        = string
  default     = "/mnt/data/libvirt/talos"
}

# Network

variable "gateway" {
  description = "Default gateway IPv4"
  type        = string
  default     = "10.0.1.1"

  validation {
    condition     = can(cidrhost("${var.gateway}/32", 0))
    error_message = "gateway must be a valid IPv4 address."
  }
}

variable "network_cidr" {
  description = "Subnet CIDR for the Talos network (e.g. 10.0.1.0/24)"
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "network_cidr must be a valid CIDR (e.g. 10.0.1.0/24)."
  }
}

# Environment
variable "schematic_path" {
  description = "Path to Talos Image Factory schematic YAML."
  type        = string
}

variable "secureboot" {
  description = "Enable UEFI SecureBoot"
  type        = bool
  default     = true
}

variable "ovmf_code_secboot" {
  description = "Path to the OVMF code binary on the host"
  type        = string
  default     = "/usr/share/edk2/ovmf/OVMF_CODE.fd"
}

variable "ovmf_vars_secboot" {
  description = "Path to the OVMF vars template on the host"
  type        = string
  default     = "/usr/share/edk2/ovmf/OVMF_VARS.fd"
}

# Image cache (libvirt-specific)
variable "talos_image_cache_dir" {
  description = "Cache dir for Talos raw images."
  type        = string
  default     = "~/.cache/talos-images"
}

# Pass-through to talos-cluster

variable "cluster_name" {
  description = "Talos / Kubernetes cluster name"
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
  default     = "1.13.9"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version must be semver X.Y.Z (e.g. 1.13.9)."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version (e.g. 1.36.1)"
  type        = string
  default     = "1.36.3"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version must be semver X.Y.Z (e.g. 1.36.3)."
  }
}

# Tailscale disabled - see ADR 001
# variable "tailscale_auth_key" {
#   description = "Tailscale key; omit to skip."
#   type        = string
#   default     = ""
#   sensitive   = true
# }

variable "longhorn_enabled" {
  description = "Enable Longhorn kubelet extraMounts. Uses /var/mnt/data when any node has data_disk_size."
  type        = bool
  default     = true
}

variable "extra_config_patches" {
  description = "Extra Talos patches (YAML) for all nodes; UserVolumeConfig auto-appended."
  type        = list(string)
  default     = []
}

variable "enable_health_check" {
  description = "Enable health gate; set false to skip on destroy."
  type        = bool
  default     = true
}

variable "drain_on_upgrade" {
  description = "Drain before Talos upgrade; keep false in prod with Longhorn."
  type        = bool
  default     = false
}
