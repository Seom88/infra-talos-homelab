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

# ── SDN runtime drift fix (PVE reboot) ──────────────────────────────────────
# PVE reboot loses SDN runtime (bridge "prod" + MASQUERADE for 10.10.0.0/24)
# while config remains — causes DNS/NTP/etcd "Waiting for time sync" deadlock
# blocking data.talos_cluster_health. bpg/proxmox sdn_applier only on diff, so
# runtime drift is never healed.
# Fix: Terraform installs pve-sdn-ensure.service on pve01 (After=
# network.target pve-cluster.service, ExecStart=pvesh set /cluster/sdn ||
# ifreload -a on boot); create enables, destroy removes.
# LIMITATION: single-node only — zone.nodes=[var.node_name] and service targets
# only ${var.ssh_username}@${coalesce(var.ssh_node_address, var.node_name)}. Multi-node
# needs zone.nodes=distinct([...proxmox_node]) and for_each on this resource.

resource "terraform_data" "sdn_ensure_applied" {
  input            = "${var.ssh_username}@${coalesce(var.ssh_node_address, var.node_name)}"
  triggers_replace = [proxmox_sdn_subnet.this.id]

  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${var.ssh_username}@${coalesce(var.ssh_node_address, var.node_name)} 'cat > /etc/systemd/system/pve-sdn-ensure.service <<'"'"'EOF'"'"'
[Unit]
Description=Ensure Proxmox SDN is applied (heal runtime drift after reboot)
After=network.target pve-cluster.service
Wants=network.target pve-cluster.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c "pvesh set /cluster/sdn 2>/dev/null || ifreload -a"
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now pve-sdn-ensure.service
pvesh set /cluster/sdn 2>/dev/null || ifreload -a
'
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes ${self.input} 'systemctl disable --now pve-sdn-ensure.service 2>/dev/null; rm -f /etc/systemd/system/pve-sdn-ensure.service; systemctl daemon-reload 2>/dev/null; echo \"pve-sdn-ensure.service removed\"'"
  }

  depends_on = [proxmox_sdn_applier.this]
}
