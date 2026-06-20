output "talosconfig" {
  description = "Talos client configuration for talosctl"
  value       = data.talos_client_configuration.client_config.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Standard kubeconfig for kubectl"
  value       = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive   = true
}

output "kubeconfig_tailscale" {
  description = "Kubeconfig with one context per Tailscale hostname. Switch with: kubectl config use-context <name>"
  sensitive   = true
  value = yamlencode({
    apiVersion      = "v1"
    kind            = "Config"
    current-context = "${var.cluster_name}-0"
    clusters = [
      for i, host in local.all_tailscale_names : {
        name = "${var.cluster_name}-${i}"
        cluster = {
          server                     = "https://${host}:6443"
          certificate-authority-data = yamldecode(talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw).clusters[0].cluster["certificate-authority-data"]
        }
      }
    ]
    contexts = [
      for i, host in local.all_tailscale_names : {
        name = "${var.cluster_name}-${i}"
        context = {
          cluster = "${var.cluster_name}-${i}"
          user    = "${var.cluster_name}-${i}"
        }
      }
    ]
    users = [
      for i, host in local.all_tailscale_names : {
        name = "${var.cluster_name}-${i}"
        user = {
          client-certificate-data = yamldecode(talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw).users[0].user["client-certificate-data"]
          client-key-data         = yamldecode(talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw).users[0].user["client-key-data"]
        }
      }
    ]
  })
}

output "machine_configuration_cp" {
  description = "Talos machine configuration for control plane nodes (for cloud-init user-data)"
  value       = data.talos_machine_configuration.control_machine_config.machine_configuration
}

output "machine_configuration_worker" {
  description = "Talos machine configuration for worker nodes (for cloud-init user-data)"
  value       = data.talos_machine_configuration.worker_machine_config.machine_configuration
}
