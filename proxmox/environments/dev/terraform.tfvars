env_name = "dev"
endpoint = "https://node.lonk-mirfak.ts.net:8006"
gateway = "192.168.2.1"
node_name = "pve"
datastore_vm = "ssd"
datastore_iso = "hdd"
insecure = true
nodes_cp = [
  {
    hostname     = "talos-dev-cp1"
    ip           = "192.168.2.231"
    cores        = 2
    memory       = 2 * 1024
    proxmox_node = "pve"
  }
]

nodes_worker = [
  {
    hostname     = "talos-dev-w1"
    ip           = "192.168.2.241"
    cores        = 2
    memory       = 2 * 1024
    proxmox_node = "pve"
  },
  {
    hostname     = "talos-dev-w2"
    ip           = "192.168.2.242"
    cores        = 2
    memory       = 2 * 1024
    proxmox_node = "pve"
  },
  {
    hostname     = "talos-dev-w3"
    ip           = "192.168.2.243"
    cores        = 2
    memory       = 2 * 1024
    proxmox_node = "pve"
  }
]

cluster_vip      = "192.168.2.230"