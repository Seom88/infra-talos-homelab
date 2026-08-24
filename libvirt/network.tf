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
          for hostname, n in local.nodes_all : {
            mac  = n.mac
            name = hostname
            ip   = n.ip
          }
        ]
      }
    }
  ]

  dns = {
    enable = "yes"
    host = [
      for hostname, n in local.nodes_all : {
        ip        = n.ip
        hostnames = [{ hostname = hostname }]
      }
    ]
  }
}
