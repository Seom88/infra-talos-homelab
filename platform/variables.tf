variable "env_name" {
  description = "Target environment (prod, dev, libvirt). Selects the kubeconfig under ../secrets/<env>/."
  type        = string
  default     = "prod"
}

variable "argocd_version" {
  description = "Exact ArgoCD Helm chart version to install (argo-helm). Bump here, never use ranges."
  type        = string
  default     = "9.5.13"
}