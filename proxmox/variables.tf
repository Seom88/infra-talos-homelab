# ============================================================
# Proxmox Provider — credentials and endpoint
# ============================================================

variable "env_name" {
  description = "Environment name for resource naming (e.g. prod, dev). Each env gets its own download + VMs so they coexist on the same PVE node."
  type        = string
}

variable "username" {
  description = "Proxmox API user (e.g. root@pam or an API token name)"
  type        = string
}

variable "password" {
  description = "Proxmox API password or API token secret"
  type        = string
  sensitive   = true
}

variable "insecure" {
  description = "Skip TLS verification for the Proxmox API (default: false)"
  type        = bool
  default     = false
}

variable "endpoint" {
  description = "Proxmox API endpoint URL (e.g. https://10.1.3.1:8006)"
  type        = string
}

# ============================================================
# Proxmox Resources — networking, storage, node settings
# ============================================================

variable "network_bridge" {
  description = "Proxmox network bridge to attach VMs to (e.g. vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "node_name" {
  description = "Proxmox node name where the Talos image will be downloaded"
  type        = string
}

variable "gateway" {
  description = "Default gateway for the VM nodes (usually your router IP)"
  type        = string
}

variable "datastore_iso" {
  description = "Proxmox datastore ID for ISO/raw images (e.g. local, hdd)"
  type        = string
  default     = "local"
}

variable "datastore_vm" {
  description = "Proxmox datastore ID for VM disks (e.g. local-lvm, ssd1)"
  type        = string
  default     = "local-lvm"
}

variable "nodes_cp" {
  description = <<-EOF
    Control plane nodes and their configurations.
    Each node requires: hostname, ip, cores, memory, proxmox_node.
  EOF
  type = list(object({
    hostname      = string
    ip            = string
    cores         = number
    memory        = number
    proxmox_node  = string
  }))
}

variable "nodes_worker" {
  description = <<-EOF
    Worker nodes and their configurations.
    Each node requires: hostname, ip, cores, memory, proxmox_node.
  EOF
  type = list(object({
    hostname      = string
    ip            = string
    cores         = number
    memory        = number
    proxmox_node  = string
  }))
}

variable "cluster_vip" {
  description = "Virtual IP for the cluster control plane (e.g. 10.1.3.10)"
  type        = string
}

# ============================================================
# Talos — shared between Proxmox image download and talos-cluster module
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
