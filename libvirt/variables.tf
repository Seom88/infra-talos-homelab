# ============================================================
# Node definitions
# ============================================================

variable "nodes_cp" {
  description = <<-EOF
    Control plane nodes.
    Required: hostname, ip, mac (static), cores, memory (MiB),
    disk_size (GiB), pool and allow_scheduling (opts this CP out of the
    control-plane taint).
  EOF
  type = list(object({
    hostname         = string
    ip               = string
    mac              = string
    cores            = number
    memory           = number
    disk_size        = number
    pool             = string
    allow_scheduling = bool
  }))
}

variable "nodes_worker" {
  description = <<-EOF
    Worker nodes.
    Required: hostname, ip, mac (static), cores, memory (MiB),
    disk_size (GiB) and pool.
  EOF
  type = list(object({
    hostname  = string
    ip        = string
    mac       = string
    cores     = number
    memory    = number
    disk_size = number
    pool      = string
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
}

# Bootstrap-only pin: bumping this replaces the node disks (etcd wipe) and
# recreates the VMs. Run 'just upgrade' / 'just upgrade-libvirt' to roll
# Talos to the latest release in place.
variable "talos_version" {
  description = "Talos Linux version (e.g. 1.13.3)"
  type        = string
  default     = "1.13.8"
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
