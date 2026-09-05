env_name         = "dev"
endpoint         = "https://pve01.lonk-mirfak.ts.net"
ssh_node_address = "pve01"
gateway          = "10.10.1.1"
node_name        = "pve01"
datastore_iso    = "local"
insecure         = true
network_bridge   = "dev"
sdn_zone         = "talos"
network_cidr     = "10.10.1.0/24"
network_snat     = true
nodes_cp = [
  {
    hostname         = "talos-cp1"
    ip               = "10.10.1.11"
    cores            = 4
    memory           = 6 * 1024
    proxmox_node     = "pve01"
    disk_size        = 25
    datastore        = "ssd01"
    allow_scheduling = true
    data_disk_size   = 50
  },
  # {
  #   hostname         = "talos-cp2"
  #   ip               = "10.10.1.12"
  #   cores            = 4
  #   memory           = 6 * 1024
  #   proxmox_node     = "pve01"
  #   disk_size        = 30
  #   datastore        = "ssd01"
  #   allow_scheduling = false
  #   data_disk_size   = 50
  # },
  # {
  #   hostname         = "talos-cp3"
  #   ip               = "10.10.1.13"
  #   cores            = 4
  #   memory           = 6 * 1024
  #   proxmox_node     = "pve01"
  #   disk_size        = 30
  #   datastore        = "ssd01"
  #   allow_scheduling = false
  #   data_disk_size   = 50
  # }
]
nodes_worker = [
  # {
  #   hostname       = "talos-w1"
  #   ip             = "10.10.1.101"
  #   cores          = 4
  #   memory         = 4 * 1024
  #   proxmox_node   = "pve01"
  #   disk_size      = 40
  #   datastore      = "ssd01"
  #   data_disk_size = 50
  # },
  # {
  #   hostname       = "talos-w2"
  #   ip             = "10.10.1.102"
  #   cores          = 4
  #   memory         = 4 * 1024
  #   proxmox_node   = "pve01"
  #   disk_size      = 40
  #   datastore      = "ssd01"
  #   data_disk_size = 50
  # },
  # {
  #   hostname       = "talos-w3"
  #   ip             = "10.10.1.103"
  #   cores          = 4
  #   memory         = 4 * 1024
  #   proxmox_node   = "pve01"
  #   disk_size      = 40
  #   datastore      = "ssd01"
  #   data_disk_size = 50
  # }
]
