output "talosconfig" {
  description = "Talos client configuration for talosctl"
  value       = module.talos.talosconfig
  sensitive   = true
}

output "kubeconfig" {
  description = "Standard kubeconfig for kubectl"
  value       = module.talos.kubeconfig
  sensitive   = true
}
