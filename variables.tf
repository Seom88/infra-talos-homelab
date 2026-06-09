# Proxmox credentials
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

# Talos image settings
variable "node_name" {
  description = "Proxmox node name where the Talos image will be downloaded"
  type        = string
}
variable "talos_image_factory_id" {
  description = "Schematic ID from the Talos Image Factory for the custom image to use"
  type        = string
  default     = "077514df2c1b6436460bc60faabc976687b16193b8a1290fda4366c69024fec2"
}
variable "talos_version" {
  description = "Talos Linux version to install on the nodes"
  type        = string
  default     = "1.13.3"
}

# Proxmox networking and storage
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

# Nodes and cluster configuration
variable "nodes" {
  description = "List of nodes and their configurations."
  type = list(object({
    hostname      = string
    ip            = string
    cores         = number
    memory        = number
    proxmox_node  = string
  }))
}
variable "cluster_name" {
  description = "Name of the Talos/Kubernetes cluster"
  type        = string
  default     = "talos-cluster"
}
variable "cluster_vip" {
  description = "Virtual IP address for the Kubernetes API (must be in the same subnet as node IPs)"
  type        = string
}
variable "kubernetes_version" {
  description = "Kubernetes version to install (e.g. 1.36.1)"
  type        = string
  default     = "1.36.1"
}

# Tailscale
variable "tailscale_auth_key" {
  description = "Tailscale pre-authentication key for node registration"
  type        = string
  sensitive   = true
}