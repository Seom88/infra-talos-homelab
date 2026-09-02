variable "nodes_cp" {
  type = list(object({
    hostname         = string
    ip               = string
    mac              = optional(string)
    cores            = number
    memory           = number
    disk_size        = number
    pool             = optional(string)
    allow_scheduling = bool
    data_disk_size   = optional(number)
    data_pool        = optional(string)
  }))
}

variable "nodes_worker" {
  type = list(object({
    hostname       = string
    ip             = string
    mac            = optional(string)
    cores          = number
    memory         = number
    disk_size      = number
    pool           = optional(string)
    data_disk_size = optional(number)
    data_pool      = optional(string)
  }))
}

variable "pool_name" {
  type    = string
  default = "talos-pool"
}

variable "pool_path" {
  type    = string
  default = "/mnt/data/libvirt/talos"
}

variable "gateway" {
  type    = string
  default = "10.0.1.1"

  validation {
    condition     = can(cidrhost("${var.gateway}/32", 0))
    error_message = "gateway must be a valid IPv4 address."
  }
}

variable "network_cidr" {
  type    = string
  default = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "network_cidr must be a valid CIDR (e.g. 10.0.1.0/24)."
  }
}

variable "secureboot" {
  type    = bool
  default = true
}

variable "ovmf_code_secboot" {
  type    = string
  default = "/usr/share/edk2/ovmf/OVMF_CODE.fd"
}

variable "ovmf_vars_secboot" {
  type    = string
  default = "/usr/share/edk2/ovmf/OVMF_VARS.fd"
}

variable "talos_image_cache_dir" {
  type    = string
  default = "~/.cache/talos-images"
}

variable "cluster_name" {
  type    = string
  default = "talos-cluster"

  validation {
    condition     = length(trimspace(var.cluster_name)) > 0
    error_message = "cluster_name must not be empty."
  }
}

variable "talos_version" {
  type    = string
  default = "1.13.9"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version must be semver X.Y.Z (e.g. 1.13.9)."
  }
}

variable "kubernetes_version" {
  type    = string
  default = "1.36.3"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version must be semver X.Y.Z (e.g. 1.36.3)."
  }
}

# Tailscale disabled - see ADR 001
# variable "tailscale_auth_key" {
#   type      = string
#   default   = ""
#   sensitive = true
# }

variable "longhorn_enabled" {
  type    = bool
  default = true
}

variable "extra_config_patches" {
  type    = list(string)
  default = []
}

# Schematic selector
# TODO: DRY duplicate across 4 envs (see ADR).
variable "env_name" {
  description = "Selects schematic-<env_name>.yaml (e.g. prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^(dev|prod)$", var.env_name))
    error_message = "env_name must be 'dev' or 'prod'."
  }
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version (exact, no ranges)."
  type        = string
  default     = "10.6.0"

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
