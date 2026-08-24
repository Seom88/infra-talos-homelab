# ============================================================
# Node definitions
# ============================================================

variable "nodes_cp" {
  description = <<-EOF
    Control plane nodes.
    Required: hostname, ip, cores, memory (MiB), disk_size (GiB),
    allow_scheduling. Optional: mac (auto-generated if omitted),
    pool (defaults to var.pool_name).
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
  }))
}

variable "nodes_worker" {
  description = <<-EOF
    Worker nodes.
    Required: hostname, ip, cores, memory (MiB), disk_size (GiB).
    Optional: mac (auto-generated if omitted), pool (defaults to var.pool_name).
  EOF
  type = list(object({
    hostname  = string
    ip        = string
    mac       = optional(string)
    cores     = number
    memory    = number
    disk_size = number
    pool      = optional(string)
  }))
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

variable "tailscale_domain" {
  description = "Tailscale MagicDNS domain (e.g. my-tailnet.ts.net)"
  type        = string
  default     = "lonk-mirfak.ts.net"
}

variable "longhorn_enabled" {
  description = "Inject kubelet extraMounts for Longhorn on all nodes"
  type        = bool
  default     = true
}

variable "extra_config_patches" {
  description = "Additional Talos machine configuration patches (raw YAML strings)"
  type        = list(string)
  default     = []
}
