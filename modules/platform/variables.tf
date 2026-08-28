variable "kubeconfig_path" {
  description = "Absolute or repo-relative path to the kubeconfig file used by the node readiness gate (terraform_data.wait_nodes). The calling root must also configure the helm provider's kubernetes.config_path to the same file. The file is typically at secrets/<provider>/<env>/kubeconfig.yaml and is materialized by `just gen-secrets` (terraform output) or by a local_file resource. If the file does not exist at plan time, wait_nodes triggers as \"kubeconfig-missing\" and helm_release is deferred via depends_on."
  type        = string

  validation {
    condition     = length(trimspace(var.kubeconfig_path)) > 0
    error_message = "kubeconfig_path must not be empty."
  }
}

variable "kubeconfig_hash" {
  description = "Optional hash of kubeconfig content to trigger re-run when cluster rotates. When null, wait_nodes is recreated only via depends_on. Prefer local_file.kubeconfig.content_base64sha256 to avoid filesha256 race on same-apply file mutation."
  type        = string
  default     = null
}

variable "argocd_version" {
  description = "Exact ArgoCD Helm chart version to install (argo-helm). Bump here, never use ranges."
  type        = string
  default     = "9.7.1"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.argocd_version))
    error_message = "argocd_version must be semver X.Y.Z (e.g. 9.5.13)."
  }
}

variable "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD will be installed. Created if it does not exist."
  type        = string
  default     = "argocd"
}

variable "argocd_values_file" {
  description = "Absolute or module-relative path to the ArgoCD Helm values file. When empty, defaults to the module's bundled values/argocd/values.yaml."
  type        = string
  default     = ""
}
