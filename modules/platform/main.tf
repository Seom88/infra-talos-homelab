# Platform: Gateway API CRDs -> Cilium (Without kube-proxy + Gateway API) -> wait nodes -> ArgoCD
# Dependency graph fix: breaks deadlock where cilium waited for nodes Ready,
# but nodes never Ready without CNI. Order: gateway-api-crds -> cilium -> wait_nodes -> argocd

# Gateway API CRDs (Helm-managed) — must be installed BEFORE Cilium
# Chart: https://github.com/christianhuth/helm-charts/tree/main/charts/gateway-api-crds
# Vendors upstream standard+experimental CRDs; standard channel is stable.
resource "helm_release" "gateway_api" {
  name             = "gateway-api-crds"
  repository       = "https://christianhuth.github.io/helm-charts"
  chart            = "gateway-api-crds"
  version          = var.gateway_api_crds_version
  namespace        = var.gateway_api_crds_namespace
  create_namespace = true
  wait             = true
  timeout          = 300

  # Standard channel enabled, experimental disabled.
  # Chart values: standard.enabled / experimental.enabled (see chart values.yaml)
  set = [
    {
      name  = "standard.enabled"
      value = var.gateway_api_channel == "standard" ? "true" : "false"
    },
    {
      name  = "experimental.enabled"
      value = var.gateway_api_channel == "experimental" ? "true" : "false"
    },
    {
      name  = "global.resourcePolicy.keep"
      value = "false"
    }
  ]
}

# Cilium — Without kube-proxy + Gateway API (Talos 1.13)
# Values from Sidero docs: https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium#cli-install
resource "helm_release" "cilium" {
  name             = "cilium"
  repository       = "https://helm.cilium.io/"
  chart            = "cilium"
  version          = var.cilium_version
  namespace        = var.cilium_namespace
  create_namespace = true
  values           = [file(var.cilium_values_file != "" ? var.cilium_values_file : "${path.module}/values/cilium/values.yaml")]
  wait             = true
  timeout          = 1800

  depends_on = [helm_release.gateway_api]

  set = [
    {
      name  = "operator.replicas"
      value = tostring(var.cilium_operator_replicas)
    }
  ]
}

# Node readiness gate — now DEPENDS on Cilium (CNI must be present for nodes to become Ready)
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

  depends_on = [helm_release.cilium]
}

# ArgoCD — depends on nodes Ready (which now implies cilium + gateway-api-crds)
# Merge pattern mirrors secured-gitops valueFiles: base values.yaml + overlay values-dev.yaml when set
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = var.argocd_namespace
  create_namespace = true
  values = var.argocd_values_file != "" ? [
    file("${path.module}/values/argocd/values.yaml"),
    file(var.argocd_values_file)
  ] : [file("${path.module}/values/argocd/values.yaml")]
  wait    = true
  timeout = 1800

  depends_on = [terraform_data.wait_nodes]
}
