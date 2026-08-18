# ── Platform layer: Longhorn (storage) + ArgoCD (GitOps) ──────────────────
# Mirrors the proven flow of repo A's infra/init-infra.sh:
#   1. Wait for all nodes to be Ready (Layer 2; Layer 1 is the proxmox
#      talos_cluster_health gate)
#   2. Create longhorn-system namespace (Carries PSA privileged labels)
#   3. Install Longhorn via Helm
#   4. Wait for Longhorn CSI (manager, driver-deployer, csi-plugin)
#   5. Apply the longhorn-prod StorageClass
#   6. Install ArgoCD via Helm (after storage, so redis-ha PVCs land safely)
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

# ── 2. longhorn-system namespace (PSA privileged labels from file) ────────
resource "kubernetes_namespace_v1" "longhorn_system" {
  metadata {
    name   = "longhorn-system"
    labels = yamldecode(file("${path.module}/values/longhorn/longhorn-namespace.yaml")).metadata.labels
  }

  depends_on = [terraform_data.wait_nodes]
}

# ── 3. Longhorn Helm release ─────────────────────
resource "helm_release" "longhorn" {
  name             = "longhorn"
  repository       = "https://charts.longhorn.io"
  chart            = "longhorn"
  version          = "1.12.1"
  namespace        = "longhorn-system"
  create_namespace = false
  values           = [file("${path.module}/values/longhorn/longhorn-values.yaml")]
  wait             = true
  timeout          = 1800

  depends_on = [
    kubernetes_namespace_v1.longhorn_system,
    terraform_data.wait_nodes
  ]
}

# ── 4. CSI readiness ───────────────
resource "terraform_data" "csi_waiter" {
  # Re-run when the kubeconfig changes (e.g. after a cluster rebuild)
  triggers_replace = {
    kubeconfig_hash = fileexists("${path.module}/../secrets/${var.env_name}/kubeconfig.yaml") ? filesha256("${path.module}/../secrets/${var.env_name}/kubeconfig.yaml") : "kubeconfig-missing"
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      export KUBECONFIG=${abspath("${path.module}/../secrets/${var.env_name}/kubeconfig.yaml")}

      # 1. Longhorn Manager DaemonSet (created by the chart)
      kubectl rollout status -n longhorn-system daemonset/longhorn-manager --timeout=10m

      # 2. Driver deployer — creates the CSI plugin DaemonSet dynamically
      kubectl rollout status -n longhorn-system deployment/longhorn-driver-deployer --timeout=5m

      # 3. CSI plugin — not in chart, created by driver-deployer after it starts
      echo "Waiting for longhorn-csi-plugin DaemonSet..."
      for i in $(seq 1 30); do
        if kubectl get daemonset longhorn-csi-plugin -n longhorn-system &>/dev/null; then
          kubectl rollout status -n longhorn-system daemonset/longhorn-csi-plugin --timeout=3m
          break
        fi
        sleep 10
      done
    EOT
  }

  depends_on = [helm_release.longhorn]
}

# ── 5. Additional StorageClass (longhorn-prod, Retain + ssd/nvme selector) ─
resource "kubernetes_manifest" "longhorn_prod_storageclass" {
  manifest = yamldecode(file("${path.module}/values/longhorn/longhorn-storageclass.yaml"))

  depends_on = [terraform_data.csi_waiter]
}

# ── 6. ArgoCD Helm release (after storage, so redis-ha PVCs land safely) ──
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.5.13"
  namespace        = "argocd"
  create_namespace = true
  values           = [file("${path.module}/values/argocd/values.yaml")]
  wait             = true
  timeout          = 1800

  depends_on = [terraform_data.csi_waiter]
}