env_name = "dev"
endpoint = "https://node.lonk-mirfak.ts.net:8006"
gateway = "10.10.10.1"
node_name = "pve"
datastore_vm = "local-lvm"
datastore_iso = "hdd"
insecure = true
network_bridge = "vnet1"
cluster_vip                        = "10.10.10.151"
disk_size_cp                       = 25
allow_scheduling_on_control_planes = true
nodes_cp = [
  {
    hostname     = "talos-dev-cp1"
    ip           = "10.10.10.152"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  },
  # {
  #   hostname     = "talos-dev-cp2"
  #   ip           = "10.10.10.153"
  #   cores        = 4
  #   memory       = 4 * 1024
  #   proxmox_node = "pve"
  # },
  # {
  #   hostname     = "talos-dev-cp3"
  #   ip           = "10.10.10.154"
  #   cores        = 4
  #   memory       = 4 * 1024
  #   proxmox_node = "pve"
  # }
]
disk_size_worker = 35
nodes_worker = [
  {
    hostname     = "talos-dev-w1"
    ip           = "10.10.10.161"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  },
  {
    hostname     = "talos-dev-w2"
    ip           = "10.10.10.162"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  },
  {
    hostname     = "talos-dev-w3"
    ip           = "10.10.10.163"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  }
]
