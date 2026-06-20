terraform {
  required_version = ">= 1.5"
  backend "local" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.109.0"
    }
    talos = {
      source = "siderolabs/talos"
    }
  }
}

provider "proxmox" {
  insecure = var.insecure
  endpoint = var.endpoint
  username = var.username
  password = var.password
}
