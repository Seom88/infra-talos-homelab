variable "machine_secrets" {
  description = "Talos machine secrets (from talos_machine_secrets resource)"
  type        = any
}

variable "client_configuration" {
  description = "Talos client configuration (from talos_machine_secrets resource)"
  type        = any
}

variable "cp_ips" {
  description = "IP addresses of all control plane nodes"
  type        = list(string)
}

variable "cp_hostnames" {
  description = "Hostnames of all control plane nodes (used for certSANs)"
  type        = list(string)
}

variable "worker_ips" {
  description = "IP addresses of all worker nodes"
  type        = list(string)
}

variable "worker_hostnames" {
  description = "Hostnames of all worker nodes"
  type        = list(string)
}

variable "cluster_name" {
  description = "Name of the Talos/Kubernetes cluster"
  type        = string
  default     = "talos-cluster"
}

variable "cluster_vip" {
  description = "Virtual IP address for the Kubernetes API endpoint"
  type        = string
}

variable "talos_version" {
  description = "Talos Linux version (e.g. 1.13.3)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to install (e.g. 1.36.1)"
  type        = string
  default     = "1.36.2"
}

variable "talos_image_id" {
  description = "Schematic ID from the Talos Image Factory"
  type        = string
}

variable "installer_image" {
  description = <<-EOF
    Installer container image used by talos_machine to keep the node OS version
    in sync (e.g. factory.talos.dev/nocloud-installer/<schematic-id>:v1.13.9).
    Must match the platform flavor of the nodes: roots booting secureboot images
    can omit it (defaults to the nocloud-installer-secureboot built from
    talos_image_id + talos_version); non-secureboot roots (e.g. libvirt) must
    override it or set secureboot=false.
  EOF
  type        = string
  default     = ""
}

variable "secureboot" {
  description = "Whether to use the secureboot installer flavor (factory.talos.dev/nocloud-installer-secureboot). Libvirt (q35 without secureboot) should set false; Proxmox (ovmf) should keep true."
  type        = bool
  default     = true
}

variable "tailscale_domain" {
  description = "Tailscale MagicDNS domain (e.g. my-tailnet.ts.net). Required only if tailscale_auth_key is set."
  type        = string
}

variable "tailscale_auth_key" {
  description = "Tailscale pre-authentication key for node registration. Omit or leave empty to skip Tailscale."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cp_allow_scheduling" {
  description = "Per control plane node: allow workloads on that node. Index-aligned with cp_hostnames / cp_ips. Each node's machine config gets cluster.allowSchedulingOnControlPlanes: true when its value is true (Talos v1.13 supports per-node machine config)."
  type        = list(bool)
}

variable "longhorn_enabled" {
  description = "Enable Longhorn support: inject kubelet extraMounts for /var/lib/longhorn on all nodes"
  type        = bool
  default     = true
}

variable "extra_config_patches" {
  description = "Additional Talos machine configuration patches (raw YAML strings) applied to all nodes (control plane + workers)"
  type        = list(string)
  default     = []
}
