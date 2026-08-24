# ============================================================
# Dedicated Storage Pool for Talos VMs & Images
# ============================================================

resource "libvirt_pool" "talos" {
  name = var.pool_name
  type = "dir"

  target = {
    path = var.pool_path
  }
}
