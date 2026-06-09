terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.109.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0"
    }
  }
}
provider "proxmox" {
  insecure  = var.insecure
  endpoint  = var.endpoint
  username = var.username
  password = var.password
}