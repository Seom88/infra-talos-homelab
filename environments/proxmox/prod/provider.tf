terraform {
  required_version = ">= 1.11"
  backend "s3" {
    bucket = "terraform-homelab"
    key    = "proxmox/prod/terraform.tfstate"
    endpoints = {
      s3 = "https://rustfs.lonk-mirfak.ts.net"
    }
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true
  }

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
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.14"
    }
  }
}

provider "proxmox" {
  insecure  = var.insecure
  endpoint  = var.endpoint
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

provider "helm" {
  kubernetes {
    config_path = "${path.module}/../../../secrets/proxmox/${var.env_name}/kubeconfig.yaml"
  }
}
