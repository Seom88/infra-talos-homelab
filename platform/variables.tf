variable "env_name" {
  description = "Target environment (prod, dev, libvirt). Selects the kubeconfig under ../secrets/<env>/."
  type        = string
  default     = "prod"
}