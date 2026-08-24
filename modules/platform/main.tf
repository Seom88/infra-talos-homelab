# ── Platform module: ArgoCD (GitOps) ─────────────────────────────────────
# Composable module called from each environment root (environments/<provider>/<env>).
# The calling root must configure the `helm` provider (kubernetes.config_path).
#
# Flow (mirrors repo's infra/init-infra.sh):
#   1. Wait for all nodes to be Ready (Layer 2; Layer 1 is the
#      talos_cluster_health gate in the infra module)
#   2. Install ArgoCD via Helm
# Longhorn is not installed here: it is deployed by the secured GitOps repo
# as a wave-0 ArgoCD app with a CSI readiness gate.
# --------------------------------------------------------------------------

# ── 1. Node readiness gate (Layer 2) ──────────────────────────────────────
resource "terraform_data" "wait_nodes" {
  # Re-run when the kubeconfig changes (e.g. after a cluster rebuild)
  triggers_replace = {
    kubeconfig_hash = fileexists(var.kubeconfig_path) ? filesha256(var.kubeconfig_path) : "kubeconfig-missing"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      export KUBECONFIG=${abspath(var.kubeconfig_path)}
      kubectl wait --for=condition=Ready node --all --timeout=600s
    EOT
  }
}

# ── 2. ArgoCD Helm release ────────────────────────────────────────────────
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
