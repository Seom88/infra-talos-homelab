endpoint = "https://node.lonk-mirfak.ts.net:8006"
gateway = "192.168.2.1"
node_name = "pve"
datastore_vm = "ssd"
datastore_iso = "hdd"
insecure = true
nodes = [
  {
    hostname = "talos-cp1"
    ip       = "192.168.2.211"
    cores    = 4
    memory   = 4 * 1024,
    proxmox_node  = "pve"
  },
  {
    hostname = "talos-cp2"
    ip       = "192.168.2.212"
    cores    = 4
    memory   = 4 * 1024,
    proxmox_node  = "pve"
  },
  {
    hostname = "talos-cp3"
    ip       = "192.168.2.213"
    cores    = 4
    memory   = 4 * 1024,
    proxmox_node  = "pve"
  }
]
cluster_vip = "192.168.2.210"
