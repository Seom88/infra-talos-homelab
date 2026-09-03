# Provider credentials
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

# Infrastructure (forwarded to module)
variable "env_name" {
  description = "Environment name (prod, dev) — used for Talos schematic filename"
  type        = string

  validation {
    condition     = can(regex("^(dev|prod)$", var.env_name))
    error_message = "env_name must be 'dev' or 'prod'."
  }
}

variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "gateway" {
  type = string

  validation {
    condition     = can(cidrhost("${var.gateway}/32", 0))
    error_message = "gateway must be a valid IPv4 address."
  }
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

  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "network_cidr must be a valid CIDR (e.g. 10.10.0.0/24)."
  }
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

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version must be semver X.Y.Z (e.g. 1.13.9)."
  }
}

# Tailscale disabled - see ADR 001
# variable "tailscale_auth_key" {
#   type      = string
#   default   = ""
#   sensitive = true
# }

variable "argocd_version" {
  description = "ArgoCD Helm chart version (exact, no ranges)."
  type        = string
  default     = "10.7.0"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.argocd_version))
    error_message = "argocd_version must be semver X.Y.Z (e.g. 9.5.13)."
  }
}

variable "enable_health_check" {
  description = "Enable health gate; set false to skip on destroy."
  type        = bool
  default     = true
}

variable "drain_on_upgrade" {
  description = "Drain before Talos upgrade; keep false in prod with Longhorn."
  type        = bool
  default     = false
}
