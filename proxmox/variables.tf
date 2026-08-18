# ============================================================
# Proxmox Provider — credentials and endpoint
# ============================================================

variable "env_name" {
  description = "Environment name for resource naming (e.g. prod, dev). Each env gets its own download + VMs so they coexist on the same PVE node."
  type        = string
}

# variable "username" {
#   description = "Proxmox API user (e.g. root@pam or an API token name)"
#   type        = string
# }

# variable "password" {
#   description = "Proxmox API password or API token secret"
#   type        = string
#   sensitive   = true
# }

variable "api_token" {
  description = "Proxmox API token in format 'user@realm!tokenid=secret'"
  type        = string
  sensitive   = true
}

variable "ssh_username" {
  description = "SSH user for Proxmox node operations (e.g. root)"
  type        = string
  default     = "root"
}

variable "ssh_node_address" {
  description = "SSH address for the Proxmox node (Tailscale hostname, e.g. node.lonk-mirfak.ts.net)"
  type        = string
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
  description = "Enable SNAT on the SDN subnet so VMs reach the internet via the node (the gateway IP is taken by the node's bridge). Disable only if an external router handles routing/NAT for the subnet"
  type        = bool
  default     = true
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
    hostname     = string
    ip           = string
    cores        = number
    memory       = number
    proxmox_node = string
  }))
}

variable "nodes_worker" {
  description = <<-EOF
    Worker nodes and their configurations.
    Each node requires: hostname, ip, cores, memory, proxmox_node.
  EOF
  type = list(object({
    hostname     = string
    ip           = string
    cores        = number
    memory       = number
    proxmox_node = string
  }))
}

variable "cluster_vip" {
  description = "Virtual IP for the cluster control plane (e.g. 10.1.3.10)"
  type        = string
}

# ============================================================
# VM disk sizes — per node type
# ============================================================

variable "disk_size_cp" {
  description = "Disk size in GB for control plane nodes"
  type        = number
  default     = 20
}

variable "disk_size_worker" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 100
}

# ============================================================
# Talos — shared between Proxmox image download and talos-cluster module
# ============================================================

variable "talos_version" {
  description = "Talos Linux version to install on the nodes (e.g. 1.13.3)"
  type        = string
  default     = "1.13.6"
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

variable "allow_scheduling_on_control_planes" {
  description = "Allow workload pods to be scheduled on control plane nodes. Pass-through to talos-cluster module."
  type        = bool
  default     = false
}

variable "tailscale_domain" {
  description = "Tailscale MagicDNS domain (e.g. my-tailnet.ts.net)"
  type        = string
  default     = "lonk-mirfak.ts.net"
}
