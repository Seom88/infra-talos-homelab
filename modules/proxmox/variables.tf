# Proxmox resources

variable "env_name" {
  description = "Env name (prod/dev); each env gets own download + VMs."
  type        = string

  validation {
    condition     = can(regex("^(dev|prod)$", var.env_name))
    error_message = "env_name must be 'dev' or 'prod'."
  }
}

variable "node_name" {
  description = "Proxmox node name where the Talos image will be downloaded"
  type        = string
}

variable "ssh_username" {
  description = "SSH user for PVE node (e.g. root)"
  type        = string
  default     = "root"
}

variable "ssh_node_address" {
  description = "SSH address for PVE node (e.g. pve01.lonk-mirfak.ts.net or Tailscale hostname)"
  type        = string
  default     = null
}

variable "gateway" {
  description = "Default gateway for the VM nodes (usually your router IP)"
  type        = string

  validation {
    condition     = can(cidrhost("${var.gateway}/32", 0))
    error_message = "gateway must be a valid IPv4 address."
  }
}

variable "datastore_iso" {
  description = "Proxmox datastore ID for ISO/raw images (e.g. local, hdd)"
  type        = string
  default     = "local"
}

variable "network_bridge" {
  description = "Bridge for VMs; with SDN must match VNet id (max 8 chars, e.g. talosvn)"
  type        = string
  default     = "vmbr0"
}

variable "sdn_zone" {
  description = "SDN zone id (each env gets own zone + VNet)"
  type        = string
  default     = "talos"
}

variable "network_cidr" {
  description = "CIDR for SDN subnet (must contain node IPs, e.g. 10.10.0.0/24)"
  type        = string
  default     = "10.10.0.0/24"

  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "network_cidr must be a valid CIDR (e.g. 10.10.0.0/24)."
  }
}

variable "network_mtu" {
  description = "MTU for the SDN zone"
  type        = number
  default     = 1500
}

variable "network_snat" {
  description = "Enable SNAT so VMs reach internet via node."
  type        = bool
  default     = true
}

variable "nodes_cp" {
  description = "Control plane nodes; optional data_disk_size creates virtio1 -> /var/mnt/data."
  type = list(object({
    hostname         = string
    ip               = string
    cores            = number
    memory           = number
    proxmox_node     = string
    disk_size        = number
    datastore        = string
    allow_scheduling = bool
    data_disk_size   = optional(number)
    data_datastore   = optional(string)
  }))

  validation {
    condition     = alltrue([for n in var.nodes_cp : n.disk_size > 0])
    error_message = "disk_size must be >0"
  }

  validation {
    condition = alltrue([
      for n in var.nodes_cp : (
        try(n.data_datastore, null) != null ? try(n.data_disk_size, null) != null : true
        ) && (
        try(n.data_disk_size, null) == null ? true : try(n.data_disk_size, 0) > 0
      )
    ])
    error_message = "data_disk_size must be >0 when set; data_datastore/data_pool requires data_disk_size"
  }
}

variable "nodes_worker" {
  description = "Worker nodes; optional data_disk_size creates virtio1 -> /var/mnt/data."
  type = list(object({
    hostname       = string
    ip             = string
    cores          = number
    memory         = number
    proxmox_node   = string
    disk_size      = number
    datastore      = string
    data_disk_size = optional(number)
    data_datastore = optional(string)
  }))

  validation {
    condition     = alltrue([for n in var.nodes_worker : n.disk_size > 0])
    error_message = "disk_size must be >0"
  }

  validation {
    condition = alltrue([
      for n in var.nodes_worker : (
        try(n.data_datastore, null) != null ? try(n.data_disk_size, null) != null : true
        ) && (
        try(n.data_disk_size, null) == null ? true : try(n.data_disk_size, 0) > 0
      )
    ])
    error_message = "data_disk_size must be >0 when set; data_datastore/data_pool requires data_disk_size"
  }
}

variable "extra_config_patches" {
  description = "Extra Talos patches (YAML) for all nodes; UserVolumeConfig auto-appended."
  type        = list(string)
  default     = []
}

# Talos version (bootstrap pin)
# DANGER: bumping replaces disks (etcd wipe); use 'just upgrade' for in-place.
variable "talos_version" {
  description = "Talos Linux version to install on the nodes (e.g. 1.13.9)"
  type        = string
  default     = "1.13.9"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version must be semver X.Y.Z (e.g. 1.13.9)."
  }
}

# Tailscale disabled - see ADR 001
# variable "tailscale_auth_key" {
#   description = "Tailscale key (pass-through to talos-cluster)."
#   type        = string
#   default     = ""
#   sensitive   = true
# }

variable "longhorn_enabled" {
  description = "Enable Longhorn extraMounts via /var/mnt/data."
  type        = bool
  default     = true
}

variable "schematic_path" {
  description = "Path to Talos Image Factory schematic YAML."
  type        = string
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
