env_name = "prod"
endpoint = "https://node.lonk-mirfak.ts.net:8006"
gateway = "10.10.10.1"
node_name = "pve"
datastore_vm = "ssd"
datastore_iso = "hdd"
insecure = true
network_bridge = "vnet1"
cluster_vip      = "10.10.10.171"
disk_size_cp     = 20
nodes_cp = [
  {
    hostname     = "talos-cp1"
    ip           = "10.10.10.172"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  }
]
disk_size_worker = 100
nodes_worker = [
  {
    hostname     = "talos-w1"
    ip           = "10.10.10.181"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  },
  {
    hostname     = "talos-w2"
    ip           = "10.10.10.182"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  },
  {
    hostname     = "talos-w3"
    ip           = "10.10.10.183"
    cores        = 4
    memory       = 4 * 1024
    proxmox_node = "pve"
  }
]
