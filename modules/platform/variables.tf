variable "kubeconfig_path" {
  description = "Path to kubeconfig file (also set in helm provider)."
  type        = string

  validation {
    condition     = length(trimspace(var.kubeconfig_path)) > 0
    error_message = "kubeconfig_path must not be empty."
  }
}

variable "kubeconfig_hash" {
  description = "Optional kubeconfig hash to trigger re-run; prefer content_base64sha256."
  type        = string
  default     = null
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version (exact, no ranges)."
  type        = string
  default     = "9.7.1"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.argocd_version))
    error_message = "argocd_version must be semver X.Y.Z (e.g. 9.5.13)."
  }
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD (created if missing)."
  type        = string
  default     = "argocd"
}

variable "argocd_values_file" {
  description = "Path to ArgoCD Helm values; defaults to module's values/argocd/values.yaml."
  type        = string
  default     = ""
}
