output "talosconfig" {
  description = "Talos client configuration for talosctl"
  value       = module.libvirt.talosconfig
  sensitive   = true
}

output "kubeconfig" {
  description = "Standard kubeconfig for kubectl"
  value       = module.libvirt.kubeconfig
  sensitive   = true
}
