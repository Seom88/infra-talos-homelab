terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.8"
    }
    talos = {
      source  = "siderolabs/talos"
      # TODO: using alpha to fix "inconsistent final plan" bug (https://github.com/siderolabs/terraform-provider-talos/issues/352).
      # Revert to stable when v0.12.0 is released.
      version = "0.12.0-alpha.5"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
