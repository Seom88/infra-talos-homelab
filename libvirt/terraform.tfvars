# ============================================================
# Libvirt / Talos Homelab — tfvars
# ============================================================

cluster_vip = "10.0.1.10"

nodes_cp = [
  {
    hostname         = "talos-cp1"
    ip               = "10.0.1.11"
    cores            = 4
    memory           = 4 * 1024
    disk_size        = 20
    allow_scheduling = false
    pool      = "talos-pool"
  },
]

nodes_worker = [
  {
    hostname  = "talos-w1"
    ip        = "10.0.1.21"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
    pool      = "talos-pool"
  },
  {
    hostname  = "talos-w2"
    ip        = "10.0.1.22"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
    pool      = "talos-pool"
  },
  {
    hostname  = "talos-w3"
    ip        = "10.0.1.23"
    cores     = 4
    memory    = 4 * 1024
    disk_size = 100
    pool      = "talos-pool"
  },
]
