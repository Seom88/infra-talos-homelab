module "proxmox" {
  source = "../../../modules/proxmox"

  env_name       = var.env_name
  node_name      = var.node_name
  gateway        = var.gateway
  datastore_iso  = var.datastore_iso
  network_bridge = var.network_bridge
  sdn_zone       = var.sdn_zone
  network_cidr   = var.network_cidr
  network_mtu    = var.network_mtu
  network_snat   = var.network_snat
  nodes_cp       = var.nodes_cp
  nodes_worker   = var.nodes_worker
  talos_version  = var.talos_version

  # Schematic path resolved relative to the repo root (3 levels up from this environment)
  schematic_path = "${path.module}/../../../schematic-${var.env_name}.yaml"

  tailscale_auth_key = var.tailscale_auth_key
  tailscale_domain   = var.tailscale_domain
}
