output "talosconfig" {
  description = "Talos client configuration for talosctl"
  value       = module.proxmox.talosconfig
  sensitive   = true
}

output "kubeconfig" {
  description = "Standard kubeconfig for kubectl"
  value       = module.proxmox.kubeconfig
  sensitive   = true
}
