terraform {
  required_version = ">= 1.11"
  backend "local" {}

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.8"
    }
    talos = {
      source = "siderolabs/talos"
      # TODO: alpha fixes inconsistent final plan (issue #352); revert to 0.12.0 when stable.
      version = "0.12.0-alpha.5"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2"
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

provider "libvirt" {
  uri = "qemu:///system"
}

provider "helm" {
  kubernetes = {
    config_path = "${path.module}/../../../secrets/libvirt/${var.env_name}/kubeconfig.yaml"
  }
}
