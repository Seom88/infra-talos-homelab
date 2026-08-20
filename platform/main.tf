# ── Platform layer: ArgoCD (GitOps) ──────────────────────────────────────
# Mirrors the proven flow of repo A's infra/init-infra.sh:
#   1. Wait for all nodes to be Ready (Layer 2; Layer 1 is the proxmox
#      talos_cluster_health gate)
#   2. Install ArgoCD via Helm
# Longhorn no longer lives here: it is deployed by the secured GitOps repo
# (secured-gitops-tailscale-homelab) as a wave-0 ArgoCD app with a CSI
# readiness gate (Job longhorn-csi-wait), so the platform root stays
# ArgoCD-only.
# --------------------------------------------------------------------------

# ── 1. Node readiness gate (Layer 2) ──────────────────────────────────────
resource "terraform_data" "wait_nodes" {
  # Re-run when the kubeconfig changes (e.g. after a cluster rebuild)
  triggers_replace = {
    kubeconfig_hash = fileexists("${path.module}/../secrets/${var.env_name}/kubeconfig.yaml") ? filesha256("${path.module}/../secrets/${var.env_name}/kubeconfig.yaml") : "kubeconfig-missing"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      export KUBECONFIG=${abspath("${path.module}/../secrets/${var.env_name}/kubeconfig.yaml")}
      kubectl wait --for=condition=Ready node --all --timeout=600s
    EOT
  }
}

# ── 2. ArgoCD Helm release ────────
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = "argocd"
  create_namespace = true
  values           = [file("${path.module}/values/argocd/values.yaml")]
  wait             = true
  timeout          = 1800

  depends_on = [terraform_data.wait_nodes]
}
