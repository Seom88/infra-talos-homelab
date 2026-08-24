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

output "kubeconfig_tailscale" {
  description = "Kubeconfig with one context per Tailscale hostname"
  value       = module.proxmox.kubeconfig_tailscale
  sensitive   = true
}
