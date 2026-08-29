# Dedicated storage pool

resource "libvirt_pool" "talos" {
  name = var.pool_name
  type = "dir"

  target = {
    path = var.pool_path
  }
}
