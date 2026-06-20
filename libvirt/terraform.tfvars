# ============================================================
# Libvirt / Talos Homelab — tfvars
# ============================================================

cluster_vip = "10.0.1.10"

nodes_cp = [
  {
    hostname = "talos-cp1"
    mac      = "52:54:00:aa:00:01"
    ip       = "10.0.1.11"
    cores    = 4
    memory   = 4 * 1024
  },
]

nodes_worker = [
  {
    hostname  = "talos-w1"
    mac       = "52:54:00:aa:00:02"
    ip        = "10.0.1.21"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
  },
  {
    hostname  = "talos-w2"
    mac       = "52:54:00:aa:00:03"
    ip        = "10.0.1.22"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
  },
  {
    hostname  = "talos-w3"
    mac       = "52:54:00:aa:00:04"
    ip        = "10.0.1.23"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
  },
]
