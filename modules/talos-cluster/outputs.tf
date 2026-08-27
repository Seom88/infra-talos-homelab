output "talosconfig" {
  description = "Talos client configuration for talosctl"
  value       = data.talos_client_configuration.client_config.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Standard kubeconfig for kubectl (via resource, sensitive — see ephemeral alternative in main.tf)"
  value       = talos_cluster_kubeconfig.kubeconfig.kubeconfig_raw
  sensitive   = true
}

output "machine_configuration_cp" {
  description = "Talos machine configuration per control plane node, keyed by hostname (for cloud-init user-data). Per-node because of the scheduling patch."
  value = {
    for hostname, config in data.talos_machine_configuration.control_machine_config : hostname => config.machine_configuration
  }
}

output "machine_configuration_worker" {
  description = "Talos machine configuration for worker nodes (for cloud-init user-data)"
  value       = data.talos_machine_configuration.worker_machine_config.machine_configuration
}
