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
  default     = "1.36.1"
}

variable "talos_image_id" {
  description = "Schematic ID from the Talos Image Factory"
  type        = string
}

variable "tailscale_domain" {
  description = "Tailscale MagicDNS domain (e.g. my-tailnet.ts.net). Required only if tailscale_auth_key is set."
  type        = string
  default     = ""
}

variable "tailscale_auth_key" {
  description = "Tailscale pre-authentication key for node registration. Omit or leave empty to skip Tailscale."
  type        = string
  default     = ""
  sensitive   = true
}
