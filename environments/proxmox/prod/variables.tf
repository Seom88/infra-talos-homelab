# ── Provider credentials ────────────────────────
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
  description = "SSH address for the Proxmox node (Tailscale hostname, e.g. node.tail-scale.ts.net)"
  type        = string
}

variable "insecure" {
  description = "Skip TLS verification for the Proxmox API"
  type        = bool
  default     = false
}

variable "endpoint" {
  description = "Proxmox API endpoint URL (e.g. https://10.1.3.1:8006)"
  type        = string
}

# ── Infrastructure variables (forwarded to module) ─────────
variable "env_name" {
  description = "Environment name (prod, dev) — used for Talos schematic filename"
  type        = string
}

variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "gateway" {
  type = string
}

variable "datastore_iso" {
  type    = string
  default = "local"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "sdn_zone" {
  type    = string
  default = "talos"
}

variable "network_cidr" {
  type    = string
  default = "10.10.0.0/24"
}

variable "network_mtu" {
  type    = number
  default = 1500
}

variable "network_snat" {
  type    = bool
  default = true
}

variable "nodes_cp" {
  type = list(object({
    hostname         = string
    ip               = string
    cores            = number
    memory           = number
    proxmox_node     = string
    disk_size        = number
    datastore        = string
    allow_scheduling = bool
    data_disk_size   = optional(number)
    data_datastore   = optional(string)
  }))
}

variable "nodes_worker" {
  type = list(object({
    hostname       = string
    ip             = string
    cores          = number
    memory         = number
    proxmox_node   = string
    disk_size      = number
    datastore      = string
    data_disk_size = optional(number)
    data_datastore = optional(string)
  }))
}

variable "talos_version" {
  type    = string
  default = "1.13.9"
}

# Tailscale extension disabled - see docs/adr/001-remove-tailscale-extension.md
# To enable: uncomment this variable AND uncomment siderolabs/tailscale in schematic-*.yaml
# variable "tailscale_auth_key" {
#   type      = string
#   default   = ""
#   sensitive = true
# }

variable "argocd_version" {
  description = "Exact ArgoCD Helm chart version to install (argo-helm). Bump here, never use ranges."
  type        = string
  default     = "9.5.13"
}

variable "enable_health_check" {
  description = "Enable post-bootstrap health gate. Set false for destroy."
  type        = bool
  default     = true
}
