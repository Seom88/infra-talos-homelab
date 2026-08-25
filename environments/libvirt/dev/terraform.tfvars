# ============================================================
# Libvirt / Talos Homelab — dev environment tfvars
# (current single-node CP + 3 workers local cluster)
# ============================================================

env_name     = "dev"
gateway      = "10.10.20.1"
network_cidr = "10.10.20.0/24"

nodes_cp = [
  {
    hostname         = "talos-cp1"
    ip               = "10.10.20.11"
    cores            = 4
    memory           = 4 * 1024
    disk_size        = 20
    allow_scheduling = false
    pool             = "talos-pool"
  },
]

nodes_worker = [
  {
    hostname       = "talos-w1"
    ip             = "10.10.20.101"
    cores          = 4
    memory         = 4 * 1024
    disk_size      = 30
    pool           = "talos-pool"
    data_disk_size = 60
  },
  {
    hostname       = "talos-w2"
    ip             = "10.10.20.102"
    cores          = 4
    memory         = 4 * 1024
    disk_size      = 30
    pool           = "talos-pool"
    data_disk_size = 60
  },
  {
    hostname       = "talos-w3"
    ip             = "10.10.20.103"
    cores          = 4
    memory         = 4 * 1024
    disk_size      = 30
    pool           = "talos-pool"
    data_disk_size = 60
  },
]
