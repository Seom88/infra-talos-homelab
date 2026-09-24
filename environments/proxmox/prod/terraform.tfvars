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

# Global datastore defaults (DRY); per-node datastore overrides.
default_datastore = "ssd01"

nodes_cp = [
  # Reserve cores 0-1 for host/TrueNAS IRQs; consolidate Talos vCPUs on 2-5,8-11 to let idle cores enter deep C-states; verify via turbostat PkgWatt/%pc10 + guest steal%.
  {
    hostname         = "talos-cp1"
    ip               = "10.10.0.11"
    cores            = 4
    memory           = 6 * 1024
    proxmox_node     = "pve01"
    disk_size        = 40
    datastore        = "local-lvm"
    allow_scheduling = false
    cpu_units        = 200
    cpu_affinity     = "2-5,8-11"
  },
  # If you wanna use more than a cp with allow_scheduling = true, use 8Gb or above and even number of cp
  # {
  #   hostname         = "talos-cp2"
  #   ip               = "10.10.0.12"
  #   cores            = 4
  #   memory           = 6 * 1024
  #   proxmox_node     = "pve01"
  #   disk_size        = 40
  #   datastore        = "local-lvm"
  #   allow_scheduling = true
  #   disks            = [{ name = "data", size = 100, datastore = "ssd01" }]
  # },
  # {
  #   hostname         = "talos-cp3"
  #   ip               = "10.10.0.13"
  #   cores            = 4
  #   memory           = 6 * 1024
  #   proxmox_node     = "pve01"
  #   disk_size        = 40
  #   datastore        = "local-lvm"
  #   allow_scheduling = true
  #   disks            = [{ name = "data", size = 100, datastore = "ssd01" }]
  # }
]
nodes_worker = [
  {
    hostname     = "talos-w1"
    ip           = "10.10.0.101"
    cores        = 6
    memory       = 6 * 1024
    proxmox_node = "pve01"
    disk_size    = 40
    datastore    = "local-lvm"
    # cpu_units    = 100
    # cpu_affinity = "2-5,8-11"
    disks = [{ name = "data", size = 150, datastore = "ssd01" }]
  },
  {
    hostname     = "talos-w2"
    ip           = "10.10.0.102"
    cores        = 6
    memory       = 6 * 1024
    proxmox_node = "pve01"
    disk_size    = 40
    datastore    = "local-lvm"
    # cpu_units    = 100
    # cpu_affinity = "2-5,8-11"
    disks = [{ name = "data", size = 150, datastore = "ssd01" }]
  },
  {
    hostname     = "talos-w3"
    ip           = "10.10.0.103"
    cores        = 6
    memory       = 6 * 1024
    proxmox_node = "pve01"
    disk_size    = 40
    datastore    = "local-lvm"
    # cpu_units    = 100
    # cpu_affinity = "2-5,8-11"
    disks = [{ name = "data", size = 150, datastore = "ssd01" }]
  },
]
