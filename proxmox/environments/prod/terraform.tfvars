env_name = "prod"
endpoint = "https://node.lonk-mirfak.ts.net:8006"
gateway = "192.168.2.1"
node_name = "pve"
datastore_vm = "ssd"
datastore_iso = "hdd"
insecure = true
nodes_cp = [
  {
    hostname     = "talos-cp1"
    ip           = "192.168.2.211"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  }
]

nodes_worker = [
  {
    hostname     = "talos-w1"
    ip           = "192.168.2.221"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  },
  {
    hostname     = "talos-w2"
    ip           = "192.168.2.222"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  },
  {
    hostname     = "talos-w3"
    ip           = "192.168.2.223"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  }
]
cluster_vip      = "192.168.2.210"
