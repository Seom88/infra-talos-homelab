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

output "schematic_id" {
  description = "Image Factory schematic ID for the canonical extension set"
  value       = module.image.schematic_id
}
