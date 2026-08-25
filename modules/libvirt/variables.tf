# ============================================================
# Node definitions
# ============================================================

variable "nodes_cp" {
  description = <<-EOF
    Control plane nodes. Required: hostname, ip, cores, memory (MiB), disk_size (GiB), allow_scheduling. Optional: mac, pool.
    Optional second disk for Longhorn: data_disk_size (GiB) creates vdb (data_pool defaults to pool; omit for single-disk).
    Auto UserVolumeConfig with diskSelector "!system_disk" -> /var/mnt/data when any node has data_disk_size.
  EOF
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
  description = <<-EOF
    Worker nodes. Required: hostname, ip, cores, memory (MiB), disk_size (GiB). Optional: mac, pool.
    Optional second disk for Longhorn: data_disk_size (GiB) creates vdb (data_pool defaults to pool; omit for single-disk).
    Auto UserVolumeConfig with diskSelector "!system_disk" -> /var/mnt/data when any node has data_disk_size.
  EOF
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

# ============================================================
# Storage Pool
# ============================================================

variable "pool_name" {
  description = "Name of the dedicated storage pool for Talos"
  type        = string
  default     = "talos-pool"
}

variable "pool_path" {
  description = "Target filesystem directory for the dedicated Talos storage pool"
  type        = string
  default     = "/var/lib/libvirt/images/talos"
}

# ============================================================
# Network
# ============================================================

variable "gateway" {
  description = "Default gateway IPv4"
  type        = string
  default     = "10.0.1.1"
}

variable "network_cidr" {
  description = "Subnet CIDR for the Talos Libvirt network (e.g. 10.0.1.0/24 or 10.10.0.0/24)"
  type        = string
  default     = "10.0.1.0/24"
}

# ============================================================
# Environment & Features
# ============================================================

variable "schematic_path" {
  description = "Absolute or root-relative path to the Talos Image Factory schematic YAML. Resolved with file()."
  type        = string
}

variable "secureboot" {
  description = "Enable UEFI SecureBoot and download secureboot-signed Talos nocloud images"
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

# ============================================================
# Talos image cache (libvirt-specific)
# ============================================================

variable "talos_image_cache_dir" {
  description = "Directory for cached Talos raw images. Must be writable by current user and readable by libvirtd/qemu."
  type        = string
  default     = "~/.cache/talos-images"
}

# ============================================================
# Pass-through — forwarded to talos-cluster module
# ============================================================

variable "cluster_name" {
  description = "Talos / Kubernetes cluster name"
  type        = string
  default     = "talos-cluster"
}

variable "talos_version" {
  description = "Talos Linux version (e.g. 1.13.3)"
  type        = string
  default     = "1.13.9"
}

variable "kubernetes_version" {
  description = "Kubernetes version (e.g. 1.36.1)"
  type        = string
  default     = "1.36.2"
}

variable "tailscale_auth_key" {
  description = "Tailscale pre-authentication key. Omit or empty to skip."
  type        = string
  default     = ""
  sensitive   = true
}

variable "longhorn_enabled" {
  description = "Enable Longhorn kubelet extraMounts. Uses /var/mnt/data when any node has data_disk_size."
  type        = bool
  default     = true
}

variable "extra_config_patches" {
  description = "Extra Talos patches (YAML strings) for all nodes. UserVolumeConfig auto-appended when any node has data_disk_size."
  type        = list(string)
  default     = []
}

variable "enable_health_check" {
  description = "Enable post-bootstrap health gate (talos_cluster_health). Set false to skip health during destroy."
  type        = bool
  default     = true
}
