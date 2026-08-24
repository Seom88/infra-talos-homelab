# ============================================================
# Libvirt Network — NAT with DHCP reservations for Talos nodes
# ============================================================

resource "libvirt_network" "talos" {
  name      = "talos-net"
  autostart = true

  forward = { mode = "nat" }

  bridge = {
    name = "virbr-talos"
    stp  = "on"
  }

  ips = [
    {
      address = "10.0.1.1"
      netmask = "255.255.255.0"
      dhcp = {
        hosts = [
          for n in concat(var.nodes_cp, var.nodes_worker) : {
            mac  = n.mac
            name = n.hostname
            ip   = n.ip
          }
        ]
      }
    }
  ]

  dns = {
    enable = "yes"
    host = [
      for n in concat(var.nodes_cp, var.nodes_worker) : {
        ip        = n.ip
        hostnames = [{ hostname = n.hostname }]
      }
    ]
  }
}
