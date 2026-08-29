# Platform: ArgoCD via Helm; env root configures helm provider.
# Flow: wait for nodes Ready -> install ArgoCD.

# Node readiness gate
resource "terraform_data" "wait_nodes" {
  # Re-run on kubeconfig change; use content hash to avoid filesha256 race.
  triggers_replace = {
    kubeconfig_hash = var.kubeconfig_hash != null ? var.kubeconfig_hash : (fileexists(var.kubeconfig_path) ? "exists" : "missing")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      export KUBECONFIG=${abspath(var.kubeconfig_path)}
      kubectl wait --for=condition=Ready node --all --timeout=600s
    EOT
  }
}

# ArgoCD
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = var.argocd_namespace
  create_namespace = true
  values           = [file(var.argocd_values_file != "" ? var.argocd_values_file : "${path.module}/values/argocd/values.yaml")]
  wait             = true
  timeout          = 1800

  depends_on = [terraform_data.wait_nodes]
}
