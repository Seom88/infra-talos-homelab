module "proxmox" {
  source = "../../../modules/proxmox"

  env_name       = var.env_name
  node_name      = var.node_name
  gateway        = var.gateway
  datastore_iso  = var.datastore_iso
  network_bridge = var.network_bridge
  sdn_zone       = var.sdn_zone
  network_cidr   = var.network_cidr
  network_mtu    = var.network_mtu
  network_snat   = var.network_snat
  nodes_cp       = var.nodes_cp
  nodes_worker   = var.nodes_worker
  talos_version  = var.talos_version

  # Schematic path resolved relative to the repo root (3 levels up from this environment)
  schematic_path = "${path.module}/../../../schematic-${var.env_name}.yaml"

  tailscale_auth_key  = var.tailscale_auth_key
  enable_health_check = var.enable_health_check
}

# ── Kubeconfig auto-generation (avoids stale file race) ──────────────────
# Writes the fresh kubeconfig from the infra module to the canonical secrets
# path BEFORE the platform layer runs. Without this, the helm provider and
# platform wait_nodes gate read a stale on-disk kubeconfig from a previous
# cluster (stale CA → x509: certificate signed by unknown authority).
# `just gen-secrets` remains as a manual fallback / setup-cli helper.
resource "local_file" "kubeconfig" {
  content         = module.proxmox.kubeconfig
  filename        = abspath("${path.root}/../../../secrets/proxmox/${var.env_name}/kubeconfig.yaml")
  file_permission = "0600"

  depends_on = [module.proxmox]
}

# ── Platform layer (ArgoCD) — composable module ──────────────────────────
module "platform" {
  source = "../../../modules/platform"

  kubeconfig_path = abspath("${path.root}/../../../secrets/proxmox/${var.env_name}/kubeconfig.yaml")
  kubeconfig_hash = local_file.kubeconfig.content_base64sha256
  argocd_version  = var.argocd_version

  depends_on = [local_file.kubeconfig]
}
