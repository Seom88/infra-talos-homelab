# SDN network: zone + VNet + subnet; VNet id == bridge name (max 8 chars).
# Applier does PUT /cluster/sdn; VMs depend on it.

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

# SDN drift fix: PVE reboot loses runtime (bridge + MASQUERADE); healed via
# pve-sdn-ensure.service. Single-node only; multi-node needs for_each.

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
