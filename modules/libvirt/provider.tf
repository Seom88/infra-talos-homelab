terraform {
  required_version = ">= 1.11"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.8"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0-alpha.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}

