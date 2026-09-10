# ============================================================
# Libvirt / Talos Homelab — dev environment tfvars
# (current single-node CP + 3 workers local cluster)
# ============================================================

env_name     = "dev"
gateway      = "10.10.20.1"
network_cidr = "10.10.20.0/24"

# Global pool defaults (DRY); per-node pool overrides.
# default_pool = "talos-pool"

nodes_cp = [
  {
    hostname         = "talos-cp1"
    ip               = "10.10.20.11"
    cores            = 8
    memory           = 10 * 1024
    disk_size        = 25
    allow_scheduling = true
    pool             = "talos-pool"
    disks            = [{ name = "data", size = 50, pool = "talos-pool" }]
  },
  # {
  #   hostname         = "talos-cp2"
  #   ip               = "10.10.20.12"
  #   cores            = 4
  #   memory           = 6 * 1024
  #   disk_size        = 25
  #   allow_scheduling = true
  #   pool             = "talos-pool"
  #   disks            = [{ name = "data", size = 50, pool = "talos-pool" }]
  # },
  # {
  #   hostname         = "talos-cp3"
  #   ip               = "10.10.20.13"
  #   cores            = 4
  #   memory           = 6 * 1024
  #   disk_size        = 25
  #   allow_scheduling = true
  #   pool             = "talos-pool"
  #   disks            = [{ name = "data", size = 50, pool = "talos-pool" }]
  # },
]

nodes_worker = [
  # {
  #   hostname  = "talos-w1"
  #   ip        = "10.10.20.101"
  #   cores     = 4
  #   memory    = 4 * 1024
  #   disk_size = 25
  #   pool      = "talos-pool"
  #   disks     = [{ name = "data", size = 50, pool = "talos-pool" }]
  # },
  # {
  #   hostname  = "talos-w2"
  #   ip        = "10.10.20.102"
  #   cores     = 4
  #   memory    = 4 * 1024
  #   disk_size = 25
  #   pool      = "talos-pool"
  #   disks     = [{ name = "data", size = 50, pool = "talos-pool" }]
  # },
  # {
  #   hostname  = "talos-w3"
  #   ip        = "10.10.20.103"
  #   cores     = 4
  #   memory    = 4 * 1024
  #   disk_size = 25
  #   pool      = "talos-pool"
  #   disks     = [{ name = "data", size = 50, pool = "talos-pool" }]
  # },
]
