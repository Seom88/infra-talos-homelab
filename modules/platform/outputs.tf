output "argocd_namespace" {
  description = "Namespace where ArgoCD was installed."
  value       = helm_release.argocd.namespace
}

output "argocd_version" {
  description = "Installed ArgoCD Helm chart version."
  value       = helm_release.argocd.version
}

output "argocd_release_name" {
  description = "Helm release name for ArgoCD."
  value       = helm_release.argocd.name
}
