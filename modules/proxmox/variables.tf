# ============================================================
# Proxmox Resources — networking, storage, node settings
# ============================================================

variable "env_name" {
  description = "Environment name for resource naming (e.g. prod, dev). Each env gets its own download + VMs so they coexist on the same PVE node."
  type        = string
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

variable "network_bridge" {
  description = "Proxmox network bridge to attach VMs to. When using SDN, this must match the SDN VNet id — max 8 chars (e.g. talosvn)"
  type        = string
  default     = "vmbr0"
}

variable "sdn_zone" {
  description = "SDN zone id for the Talos network. Each environment gets its own zone + VNet"
  type        = string
  default     = "talos"
}

variable "network_cidr" {
  description = "CIDR for the SDN VNet subnet. Must contain the node IPs (e.g. 10.10.0.0/24)"
  type        = string
  default     = "10.10.0.0/24"
}

variable "network_mtu" {
  description = "MTU for the SDN zone"
  type        = number
  default     = 1500
}

variable "network_snat" {
  description = "Enable SNAT on the SDN subnet so VMs reach the internet via the node. Disable only if an external router handles routing/NAT for the subnet"
  type        = bool
  default     = true
}

variable "nodes_cp" {
  description = <<-EOF
    Control plane nodes and their configurations.
    Each node requires: hostname, ip, cores, memory, proxmox_node,
    per-node disk_size (GB) and datastore; allow_scheduling opts this CP
    out of the control-plane taint.
  EOF
  type = list(object({
    hostname         = string
    ip               = string
    cores            = number
    memory           = number
    proxmox_node     = string
    disk_size        = number
    datastore        = string
    allow_scheduling = bool
  }))
}

variable "nodes_worker" {
  description = <<-EOF
    Worker nodes and their configurations.
    Each node requires: hostname, ip, cores, memory, proxmox_node,
    per-node disk_size (GB) and datastore.
  EOF
  type = list(object({
    hostname     = string
    ip           = string
    cores        = number
    memory       = number
    proxmox_node = string
    disk_size    = number
    datastore    = string
  }))
}

# ============================================================
# Talos — shared between Proxmox image download and talos-cluster module
# ============================================================

# Bootstrap-only pin: bumping this replaces the node disks (etcd wipe) and
# recreates the VMs. Run 'just upgrade' to roll Talos in-place via talos_machine.image.
variable "talos_version" {
  description = "Talos Linux version to install on the nodes (e.g. 1.13.9)"
  type        = string
  default     = "1.13.9"
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

# ============================================================
# Schematic
# ============================================================

variable "schematic_path" {
  description = "Absolute or root-relative path to the Talos Image Factory schematic YAML (e.g. schematic-prod.yaml). Resolved with file()."
  type        = string
}
