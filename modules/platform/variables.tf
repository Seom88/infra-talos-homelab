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

# Cilium
variable "cilium_version" {
  description = "Cilium Helm chart version (exact, no ranges). Sidero guide pins 1.18.0, Cilium stable docs (2025-09) requires 1.20.1 for Gateway API v1.6.1."
  type        = string
  default     = "1.20.1"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.cilium_version))
    error_message = "cilium_version must be semver X.Y.Z (e.g. 1.18.0)."
  }
}

variable "cilium_namespace" {
  description = "Namespace for Cilium (created if missing)."
  type        = string
  default     = "kube-system"
}

variable "cilium_values_file" {
  description = "Path to Cilium Helm values; defaults to module's values/cilium/values.yaml."
  type        = string
  default     = ""
}

variable "cilium_operator_replicas" {
  description = "Cilium operator replicas. Use 1 for single-node/dev (RAM constrained), 2 for HA with 3+ nodes. Leader election handles active/standby."
  type        = number
  default     = 1

  validation {
    condition     = var.cilium_operator_replicas >= 1 && var.cilium_operator_replicas <= 3
    error_message = "cilium_operator_replicas must be 1-3."
  }
}

# Gateway API CRDs (Helm-managed, must install BEFORE Cilium)
# Chart: christianhuth/gateway-api-crds — version is the chart version (1.2.3 -> app v1.6.1, CRDs standard 1.2.1)
variable "gateway_api_crds_version" {
  description = "Gateway API CRDs Helm chart version (christianhuth/gateway-api-crds)."
  type        = string
  default     = "1.2.3"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.gateway_api_crds_version))
    error_message = "gateway_api_crds_version must be semver X.Y.Z (e.g. 1.2.3)."
  }
}

variable "gateway_api_crds_namespace" {
  description = "Namespace for Gateway API CRDs Helm release (CRDs are cluster-scoped; Helm still needs a namespace)."
  type        = string
  default     = "kube-system"
}

# Alias for compatibility with older naming (task requires gateway_api_version)
variable "gateway_api_version" {
  description = "Alias for gateway_api_crds_version (Gateway API CRDs Helm chart version)."
  type        = string
  default     = "1.2.3"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.gateway_api_version))
    error_message = "gateway_api_version must be semver X.Y.Z (e.g. 1.2.3)."
  }
}

variable "gateway_api_channel" {
  description = "Gateway API channel: standard (stable) or experimental. Used only for documentation; chart uses standard.enabled / experimental.enabled."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "experimental"], var.gateway_api_channel)
    error_message = "gateway_api_channel must be 'standard' or 'experimental'."
  }
}

# ArgoCD
variable "argocd_version" {
  description = "ArgoCD Helm chart version (exact, no ranges)."
  type        = string
  default     = "10.7.0"

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
