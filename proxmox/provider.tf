terraform {
  required_version = ">= 1.5"
  backend "local" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.1"
    }
    talos = {
      source = "siderolabs/talos"
      # TODO: using alpha to fix "inconsistent final plan" bug (https://github.com/siderolabs/terraform-provider-talos/issues/352).
      # Revert to stable when v0.12.0 is released.
      version = "0.12.0-alpha.5"
    }
  }
}

provider "proxmox" {
  insecure = var.insecure
  endpoint = var.endpoint

  # User authentication via username/password
  # username = var.username
  # password = var.password

  # Token authentication via API token
  api_token = var.api_token
  ssh {
    agent    = true
    username = var.ssh_username
    node {
      name    = var.node_name
      address = var.ssh_node_address
    }
  }

}
