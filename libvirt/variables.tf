# ============================================================
# Network
# ============================================================

variable "gateway" {
  description = "Default gateway for the VM nodes (usually your router IP)"
  type        = string
}

# ============================================================
# Node definitions
# ============================================================

variable "nodes_cp" {
  description = <<-EOF
    Control plane nodes and their configurations.
    Each node requires: hostname, ip, cores, memory.
    disk_size defaults to 20 (GiB).
  EOF
  type = list(object({
    hostname  = string
    ip        = string
    cores     = number
    memory    = number
    disk_size = optional(number, 20)
  }))
}

variable "nodes_worker" {
  description = <<-EOF
    Worker nodes and their configurations.
    Each node requires: hostname, ip, cores, memory.
    disk_size defaults to 100 (GiB).
  EOF
  type = list(object({
    hostname  = string
    ip        = string
    cores     = number
    memory    = number
    disk_size = optional(number, 100)
  }))
}

# ============================================================
# Talos — shared between image download and talos-cluster module
# ============================================================

variable "talos_image_factory_id" {
  description = "Schematic ID from the Talos Image Factory for the custom image to use"
  type        = string
  default     = "077514df2c1b6436460bc60faabc976687b16193b8a1290fda4366c69024fec2"
}

variable "talos_version" {
  description = "Talos Linux version to install on the nodes (e.g. 1.13.3)"
  type        = string
  default     = "1.13.3"
}

# ============================================================
# Module pass-through — forwarded to talos-cluster module
# ============================================================

variable "tailscale_auth_key" {
  description = "Tailscale pre-authentication key. Pass-through to talos-cluster module. Omit or set empty to skip Tailscale."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cluster_vip" {
  description = "Virtual IP address for the Kubernetes API endpoint (VIP or first CP IP)"
  type        = string
  default     = "192.168.2.210"
}

variable "tailscale_domain" {
  description = "Tailscale MagicDNS domain (e.g. my-tailnet.ts.net). Required only if tailscale_auth_key is set."
  type        = string
  default     = "lonk-mirfak.ts.net"
}

# ============================================================
# Libvirt specific — image cache path
# ============================================================

variable "talos_image_cache_dir" {
  description = "Local directory to cache the downloaded Talos raw image. Must be writable by the user running Terraform and readable by libvirt."
  type        = string
  default     = "/tmp/talos-images"
}
