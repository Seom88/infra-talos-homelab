# ============================================================
# Wait for first control plane Talos API
# ============================================================

resource "terraform_data" "wait_for_cp" {
  provisioner "local-exec" {
    command = <<-EOT
      IP="${var.nodes_cp[0].ip}"
      echo "Waiting for ${var.nodes_cp[0].hostname} ($${IP})..."
      for i in $(seq 1 30); do
        if timeout 3 bash -c "echo > /dev/tcp/$${IP}/50000" 2>/dev/null \
           || timeout 3 bash -c "echo > /dev/tcp/$${IP}/6443" 2>/dev/null; then
          exit 0
        fi
        sleep 10
      done
      exit 1
    EOT
  }

  depends_on = [libvirt_domain.node]
}

# ============================================================
# Talos Cluster — apply, bootstrap, kubeconfig
# ============================================================

module "talos_cluster" {
  source = "../modules/talos-cluster"

  machine_secrets      = talos_machine_secrets.this.machine_secrets
  client_configuration = talos_machine_secrets.this.client_configuration
  cp_ips               = local.cp_ips
  cp_hostnames         = [for n in var.nodes_cp : n.hostname]
  worker_ips           = [for n in var.nodes_worker : n.ip]
  worker_hostnames     = [for n in var.nodes_worker : n.hostname]
  cluster_name         = var.cluster_name
  cluster_vip          = var.cluster_vip
  talos_version        = var.talos_version
  kubernetes_version   = var.kubernetes_version
  talos_image_id       = talos_image_factory_schematic.this.id
  secureboot           = var.secureboot
  tailscale_domain     = var.tailscale_domain
  tailscale_auth_key   = var.tailscale_auth_key
  cp_allow_scheduling  = [for n in var.nodes_cp : n.allow_scheduling]
  longhorn_enabled     = var.longhorn_enabled
  extra_config_patches = var.extra_config_patches

  depends_on = [
    terraform_data.wait_for_cp,
  ]
}

# ── Cluster Health Gate ─────────────────────────
# Blocks apply until kube-apiserver, etcd, and all nodes are Ready,
# so dependent roots (platform/) never race the cluster bootstrap.
data "talos_cluster_health" "this" {
  depends_on           = [module.talos_cluster]
  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [for node in var.nodes_cp : node.ip]
  worker_nodes         = [for node in var.nodes_worker : node.ip]
  endpoints            = [for node in var.nodes_cp : node.ip]
  timeouts = {
    read = "15m"
  }
}
