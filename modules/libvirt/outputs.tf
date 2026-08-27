output "talosconfig" {
  description = "Talos client configuration for talosctl"
  value       = module.talos_cluster.talosconfig
  sensitive   = true
}

output "kubeconfig" {
  description = "Standard kubeconfig for kubectl"
  value       = module.talos_cluster.kubeconfig
  sensitive   = true
}
