# ============================================================
# Libvirt / Talos Homelab — tfvars
# ============================================================

gateway = "192.168.2.1"

nodes_cp = [
  {
    hostname = "talos-cp1"
    ip       = "192.168.2.211"
    cores    = 4
    memory   = 4 * 1024
  },
]

nodes_worker = [
  {
    hostname  = "talos-w1"
    ip        = "192.168.2.221"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
  },
  {
    hostname  = "talos-w2"
    ip        = "192.168.2.222"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
  },
  {
    hostname  = "talos-w3"
    ip        = "192.168.2.223"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
  },
]
