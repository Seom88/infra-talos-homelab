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
  }))
}

variable "nodes_worker" {
  type = list(object({
    hostname  = string
    ip        = string
    mac       = optional(string)
    cores     = number
    memory    = number
    disk_size = number
    pool      = optional(string)
  }))
}

variable "pool_name" {
  type    = string
  default = "talos-pool"
}

variable "pool_path" {
  type    = string
  default = "/var/lib/libvirt/images/talos"
}

variable "gateway" {
  type    = string
  default = "10.0.1.1"
}

variable "network_cidr" {
  type    = string
  default = "10.0.1.0/24"
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
}

variable "talos_version" {
  type    = string
  default = "1.13.9"
}

variable "kubernetes_version" {
  type    = string
  default = "1.36.2"
}

variable "tailscale_auth_key" {
  type      = string
  default   = ""
  sensitive = true
}

variable "tailscale_domain" {
  type    = string
  default = "lonk-mirfak.ts.net"
}

variable "longhorn_enabled" {
  type    = bool
  default = true
}

variable "extra_config_patches" {
  type    = list(string)
  default = []
}

# Schematic env selector (e.g. "dev", "prod")
variable "env_name" {
  description = "Selects which schematic-<env_name>.yaml is used (e.g. dev → schematic-dev.yaml)"
  type        = string
  default     = "dev"
}
