env_name         = "dev"
endpoint         = "https://pve01.lonk-mirfak.ts.net:8006"
ssh_node_address = "pve01.lonk-mirfak.ts.net"
gateway          = "10.10.1.1"
node_name        = "pve01"
datastore_vm     = "ssd01"
datastore_iso    = "local"
insecure         = true
network_bridge   = "talosvn"
sdn_zone         = "dev"
network_cidr     = "10.10.1.0/24"
cluster_vip      = "10.10.1.171"
disk_size_cp     = 25
# allow_scheduling_on_control_planes = true
nodes_cp = [
  {
    hostname     = "talos-cp1"
    ip           = "10.10.1.172"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve01"
  },
  # {
  #   hostname     = "talos-cp2"
  #   ip           = "10.10.1.173"
  #   cores        = 4
  #   memory       = 6 * 1024
  #   proxmox_node = "pve01"
  # },
  # {
  #   hostname     = "talos-cp3"
  #   ip           = "10.10.1.174"
  #   cores        = 4
  #   memory       = 6 * 1024
  #   proxmox_node = "pve01"
  # }
]
disk_size_worker = 100
nodes_worker = [
  {
    hostname     = "talos-w1"
    ip           = "10.10.1.181"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve01"
  },
  {
    hostname     = "talos-w2"
    ip           = "10.10.1.182"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve01"
  },
  {
    hostname     = "talos-w3"
    ip           = "10.10.1.183"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve01"
  }
]
