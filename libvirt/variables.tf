# ============================================================
# Node definitions
# ============================================================

variable "nodes_cp" {
  description = <<-EOF
    Control plane nodes.
    Required: hostname, ip, mac (static), cores, memory (MiB).
    disk_size defaults to 20 GiB.
  EOF
  type = list(object({
    hostname  = string
    ip        = string
    mac       = string
    cores     = number
    memory    = number
    disk_size = optional(number, 20)
  }))
}

variable "nodes_worker" {
  description = <<-EOF
    Worker nodes.
    Required: hostname, ip, mac (static), cores, memory (MiB).
    disk_size defaults to 100 GiB.
  EOF
  type = list(object({
    hostname  = string
    ip        = string
    mac       = string
    cores     = number
    memory    = number
    disk_size = optional(number, 100)
  }))
}

# ============================================================
# Network
# ============================================================

variable "gateway" {
  description = "Default gateway IPv4"
  type        = string
  default     = "10.0.1.1"
}

variable "network_prefix" {
  description = "CIDR prefix length (e.g. 24 for /24)"
  type        = number
  default     = 24
}

# ============================================================
# Environment
# ============================================================

variable "schematic_name" {
  description = "Schematic YAML filename (e.g. schematic-dev.yaml). Overrides env_name if set."
  type        = string
  default     = "schematic-dev.yaml"
}

# ============================================================
# Talos image cache (libvirt-specific)
# ============================================================

variable "talos_image_cache_dir" {
  description = "Local directory for cached Talos raw images. Must be readable by libvirtd."
  type        = string
  default     = "/tmp/talos-images"
}

# ============================================================
# Pass-through — forwarded to talos-cluster module
# ============================================================

variable "cluster_name" {
  description = "Talos / Kubernetes cluster name"
  type        = string
  default     = "talos-cluster"
}

variable "cluster_vip" {
  description = "Virtual IP address for the Kubernetes API endpoint"
  type        = string
  default     = "192.168.122.210"
}

variable "talos_version" {
  description = "Talos Linux version (e.g. 1.13.3)"
  type        = string
  default     = "1.13.3"
}

variable "kubernetes_version" {
  description = "Kubernetes version (e.g. 1.36.1)"
  type        = string
  default     = "1.36.1"
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

variable "allow_scheduling_on_control_planes" {
  description = "Allow workloads on control plane nodes"
  type        = bool
  default     = false
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
