# ── SDN Network (Talos) ───────────────────────────
# Creates the SDN zone + VNet (bridge) + subnet that the VMs attach to.
# The VNet id is the Linux bridge name on the node (e.g. talosvn; PVE caps VNet ids at 8 chars),
# so it must match var.network_bridge used by the VMs.
#
# Order matters: the applier resource performs the actual SDN "Apply"
# (PUT /cluster/sdn) — without it the bridge does not exist on the node
# and VM creation fails. The applier depends on all SDN resources, and
# the VMs depend on the applier.

resource "proxmox_sdn_zone_simple" "this" {
  id    = var.sdn_zone
  nodes = [var.node_name]
  mtu   = var.network_mtu
}

resource "proxmox_sdn_vnet" "this" {
  id   = var.network_bridge
  zone = proxmox_sdn_zone_simple.this.id
}

resource "proxmox_sdn_subnet" "this" {
  cidr    = var.network_cidr
  gateway = var.gateway
  snat    = var.network_snat
  vnet    = proxmox_sdn_vnet.this.id
}

resource "proxmox_sdn_applier" "this" {
  lifecycle {
    replace_triggered_by = [
      proxmox_sdn_zone_simple.this,
      proxmox_sdn_vnet.this,
      proxmox_sdn_subnet.this,
    ]
  }

  depends_on = [
    proxmox_sdn_zone_simple.this,
    proxmox_sdn_vnet.this,
    proxmox_sdn_subnet.this,
  ]
}
