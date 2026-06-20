locals {
  tailscale_cp_hostnames     = var.tailscale_domain != "" ? [for n in var.nodes_cp : "${n.hostname}.${var.tailscale_domain}"] : []
  tailscale_worker_hostnames = var.tailscale_domain != "" ? [for n in var.nodes_worker : "${n.hostname}.${var.tailscale_domain}"] : []
  all_tailscale_hostnames    = concat(local.tailscale_cp_hostnames, local.tailscale_worker_hostnames)
}

output "talosconfig" {
  description = "Talos client configuration for talosctl"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Standard kubeconfig for kubectl"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "kubeconfig_tailscale" {
  description = <<-EOF
    Kubeconfig with one context per Tailscale hostname.
    Switch contexts with: kubectl config use-context <name>
  EOF
  sensitive   = true
  value = length(local.all_tailscale_hostnames) > 0 ? yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "${var.cluster_name}-0"
    clusters = [
      for i, host in local.all_tailscale_hostnames : {
        name = "${var.cluster_name}-${i}"
        cluster = {
          server                     = "https://${host}:6443"
          certificate-authority-data = yamldecode(talos_cluster_kubeconfig.this.kubeconfig_raw).clusters[0].cluster["certificate-authority-data"]
        }
      }
    ]
    contexts = [
      for i, host in local.all_tailscale_hostnames : {
        name = "${var.cluster_name}-${i}"
        context = {
          cluster = "${var.cluster_name}-${i}"
          user    = "${var.cluster_name}-${i}"
        }
      }
    ]
    users = [
      for i, host in local.all_tailscale_hostnames : {
        name = "${var.cluster_name}-${i}"
        user = {
          client-certificate-data = yamldecode(talos_cluster_kubeconfig.this.kubeconfig_raw).users[0].user["client-certificate-data"]
          client-key-data         = yamldecode(talos_cluster_kubeconfig.this.kubeconfig_raw).users[0].user["client-key-data"]
        }
      }
    ]
  }) : null
}
