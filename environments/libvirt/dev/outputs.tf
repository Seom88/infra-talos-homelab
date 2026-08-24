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

output "kubeconfig_tailscale" {
  description = "Kubeconfig with one context per Tailscale hostname. Switch with: kubectl config use-context <name>"
  sensitive   = true
  value       = module.libvirt.kubeconfig_tailscale
}
