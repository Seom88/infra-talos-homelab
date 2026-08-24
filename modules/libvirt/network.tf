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
    zone = "libvirt"
  }

  ips = [
    {
      address = var.gateway
      netmask = cidrnetmask(var.network_cidr)
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
    forwarders = [
      { addr = "1.1.1.1" },
      { addr = "8.8.8.8" },
    ]
    host = [
      for hostname, n in local.nodes_all : {
        ip        = n.ip
        hostnames = [{ hostname = hostname }]
      }
    ]
  }
}
