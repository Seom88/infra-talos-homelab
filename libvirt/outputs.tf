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

output "kubeconfig_tailscale" {
  description = "Kubeconfig with one context per Tailscale hostname"
  value       = module.talos.kubeconfig_tailscale
  sensitive   = true
}
