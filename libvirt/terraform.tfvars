# ============================================================
# Libvirt / Talos Homelab — tfvars
# ============================================================

cluster_vip = "192.168.122.210"

nodes_cp = [
  {
    hostname = "talos-cp1"
    mac      = "52:54:00:aa:00:01"
    ip       = "192.168.122.211"
    cores    = 4
    memory   = 4 * 1024
  },
]

nodes_worker = [
  {
    hostname  = "talos-w1"
    mac       = "52:54:00:aa:00:02"
    ip        = "192.168.122.221"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
  },
  {
    hostname  = "talos-w2"
    mac       = "52:54:00:aa:00:03"
    ip        = "192.168.122.222"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
  },
  {
    hostname  = "talos-w3"
    mac       = "52:54:00:aa:00:04"
    ip        = "192.168.122.223"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
  },
]
