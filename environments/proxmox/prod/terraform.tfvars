env_name         = "prod"
endpoint         = "https://pve01.lonk-mirfak.ts.net"
ssh_node_address = "pve01"
gateway          = "10.10.0.1"
node_name        = "pve01"
datastore_iso    = "local"
network_bridge   = "prod"
sdn_zone         = "talosvn"
network_cidr     = "10.10.0.0/24"
network_snat     = true
nodes_cp = [
  {
    hostname         = "talos-cp1"
    ip               = "10.10.0.11"
    cores            = 4
    memory           = 6 * 1024
    proxmox_node     = "pve01"
    disk_size        = 40
    datastore        = "ssd01"
    allow_scheduling = true
    data_disk_size   = 100
  },
  {
    hostname         = "talos-cp2"
    ip               = "10.10.0.12"
    cores            = 4
    memory           = 6 * 1024
    proxmox_node     = "pve01"
    disk_size        = 40
    datastore        = "ssd01"
    allow_scheduling = true
    data_disk_size   = 100
  },
  {
    hostname         = "talos-cp3"
    ip               = "10.10.0.13"
    cores            = 4
    memory           = 6 * 1024
    proxmox_node     = "pve01"
    disk_size        = 40
    datastore        = "ssd01"
    allow_scheduling = true
    data_disk_size   = 100
  }
]
nodes_worker = [
  # {
  #   hostname       = "talos-w1"
  #   ip             = "10.10.0.101"
  #   cores          = 4
  #   memory         = 4 * 1024
  #   proxmox_node   = "pve01"
  #   disk_size      = 40
  #   datastore      = "ssd01"
  #   data_disk_size = 100
  # },
  # {
  #   hostname       = "talos-w2"
  #   ip             = "10.10.0.102"
  #   cores          = 4
  #   memory         = 4 * 1024
  #   proxmox_node   = "pve01"
  #   disk_size      = 40
  #   datastore      = "ssd01"
  #   data_disk_size = 100
  # },
  # {
  #   hostname       = "talos-w3"
  #   ip             = "10.10.0.103"
  #   cores          = 4
  #   memory         = 4 * 1024
  #   proxmox_node   = "pve01"
  #   disk_size      = 40
  #   datastore      = "ssd01"
  #   data_disk_size = 100
  # },
]
