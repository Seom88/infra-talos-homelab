# ============================================================
# Libvirt / Talos Homelab — prod environment tfvars
# Placeholder for homelab server migration to libvirt.
# ============================================================

env_name     = "prod"
gateway      = "10.10.10.1"
network_cidr = "10.10.10.0/24"

nodes_cp = [
  {
    hostname         = "talos-cp1"
    ip               = "10.10.10.11"
    cores            = 4
    memory           = 6 * 1024
    disk_size        = 25
    allow_scheduling = false
    pool             = "talos-pool"
  },
  #   {
  #     hostname         = "talos-cp2"
  #     ip               = "10.10.10.12"
  #     cores            = 4
  #     memory           = 8 * 1024
  #     disk_size        = 100
  #     allow_scheduling = true
  #     pool             = "talos-pool"
  #   },
  #   {
  #     hostname         = "talos-cp3"
  #     ip               = "10.10.10.13"
  #     cores            = 4
  #     memory           = 8 * 1024
  #     disk_size        = 100
  #     allow_scheduling = true
  #     pool             = "talos-pool"
  #   },
]

nodes_worker = [
  {
    hostname  = "talos-w1"
    ip        = "10.10.10.101"
    cores     = 8
    memory    = 4 * 1024
    disk_size = 100
    pool      = "talos-pool"
  },
  {
    hostname  = "talos-w2"
    ip        = "10.10.10.102"
    cores     = 8
    memory    = 4 * 1024
    disk_size = 100
    pool      = "talos-pool"
  },
  {
    hostname  = "talos-w3"
    ip        = "10.10.10.103"
    cores     = 8
    memory    = 4 * 1024
    disk_size = 100
    pool      = "talos-pool"
  },
]
