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
  default     = "192.168.122.1"
}

variable "network_prefix" {
  description = "CIDR prefix length (e.g. 24 for /24)"
  type        = number
  default     = 24
}

# ============================================================
# Cluster
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

# ============================================================
# Environment
# ============================================================

variable "env_name" {
  description = "Environment name. Selects which schematic YAML to use (e.g. schematic-dev.yaml or schematic-prod.yaml)."
  type        = string
  default     = "dev"
}

# ============================================================
# Talos versions
# ============================================================

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

# ============================================================
# Tailscale
# ============================================================

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

# ============================================================
# Scheduling & extras
# ============================================================

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

# ============================================================
# Libvirt paths
# ============================================================

variable "talos_image_cache_dir" {
  description = "Local directory for cached Talos raw images. Must be readable by libvirtd."
  type        = string
  default     = "/tmp/talos-images"
}
