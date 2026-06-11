# ============================================================
# Locals — merge all nodes into one map for for_each
# ============================================================

locals {
  nodes_all = merge(
    { for n in var.nodes_cp : n.hostname => {
      role      = "cp"
      ip        = n.ip
      cores     = n.cores
      memory    = n.memory
      disk_size = n.disk_size
    } },
    { for n in var.nodes_worker : n.hostname => {
      role      = "worker"
      ip        = n.ip
      cores     = n.cores
      memory    = n.memory
      disk_size = n.disk_size
    } },
  )

  cp_ips           = [for n in var.nodes_cp : n.ip]
  cp_hostnames     = [for n in var.nodes_cp : n.hostname]
  worker_ips       = [for n in var.nodes_worker : n.ip]
  worker_hostnames = [for n in var.nodes_worker : n.hostname]
}

# ============================================================
# 1. Image cache — download Talos qcow2 once
# ============================================================

resource "terraform_data" "talos_image" {
  triggers_replace = var.talos_version

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      IMAGE_DIR="${var.talos_image_cache_dir}"
      QCOW2_PATH="$${IMAGE_DIR}/talos-v${var.talos_version}.qcow2"
      QCOW2_XZ_PATH="$${QCOW2_PATH}.xz"
      mkdir -p "$${IMAGE_DIR}"
      if [ -f "$${QCOW2_PATH}" ]; then
        echo "qcow2 image already exists: $${QCOW2_PATH}"
        exit 0
      fi
      echo "Downloading Talos qcow2 image v${var.talos_version}..."
      curl -fsSL -o "$${QCOW2_XZ_PATH}" \
        "https://factory.talos.dev/image/${var.talos_image_factory_id}/v${var.talos_version}/nocloud-amd64.qcow2.xz"
      echo "Decompressing..."
      xz -d -f "$${QCOW2_XZ_PATH}"
      echo "Done: $${QCOW2_PATH}"
    EOT
  }
}

# ============================================================
# 2. Root disks per node — full copy from cached qcow2
#    (backing_store not supported by the default pool)
# ============================================================

resource "libvirt_volume" "node_root" {
  for_each = local.nodes_all
  name     = "${each.key}.qcow2"
  pool     = "default"
  create = {
    content = {
      url = "file://${var.talos_image_cache_dir}/talos-v${var.talos_version}.qcow2"
    }
  }
  depends_on = [terraform_data.talos_image]
}

# ============================================================
# 3. Cloud-init per node — network config + minimal user_data
#    Talos NoCloud reads network-config from this ISO
# ============================================================

resource "libvirt_cloudinit_disk" "node" {
  for_each = local.nodes_all
  name     = "${each.key}-init"

  meta_data = yamlencode({
    instance-id    = each.key
    local-hostname = each.key
  })

  # v1 format — matches Talos nocloud docs example
  network_config = yamlencode({
    version = 1
    config = [
      {
        type = "physical"
        name = "eth0"
        subnets = [
          {
            type    = "static"
            address = each.value.ip
            netmask = "255.255.255.0"
            gateway = var.gateway
          }
        ]
      }
    ]
  })

  user_data = "# Talos machine config applied by talos-cluster module\n"
}

resource "libvirt_volume" "node_cloudinit" {
  for_each = local.nodes_all
  name     = "${each.key}-init.iso"
  pool     = "default"
  create = {
    content = {
      url = libvirt_cloudinit_disk.node[each.key].path
    }
  }
  lifecycle {
    ignore_changes = [target]
  }
}

# ============================================================
# 4. VM domains per node
#    UEFI firmware — required to pass talos.platform=nocloud
#    via <os cmdline> (SeaBIOS doesn't support -append without
#    -kernel). Mirrors rgl/terraform-libvirt-talos approach.
# ============================================================

resource "libvirt_domain" "node" {
  for_each = local.nodes_all

  name        = each.key
  type        = "kvm"
  memory      = each.value.memory
  memory_unit = "MiB"
  vcpu        = each.value.cores
  autostart   = true
  running     = true

  cpu = {
    mode = "host-passthrough"
  }

  features = {
    acpi = true
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    firmware     = "efi"
    boot_devices = [
      { dev = "hd" }
    ]
    # No cmdline — Image Factory's nocloud image has
    # talos.platform=nocloud baked into the bootloader,
    # which triggers cidata CDROM detection automatically
  }

  devices = {
    disks = [
      {
        source = {
          file = {
            file = libvirt_volume.node_root[each.key].path
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        device = "cdrom"
        source = {
          file = {
            file = libvirt_volume.node_cloudinit[each.key].path
          }
        }
        target = {
          dev = "sdb"
          bus = "sata"
        }
      },
    ]

    interfaces = [
      {
        model = { type = "virtio" }
        source = {
          network = {
            network = "default"
          }
        }
      },
    ]
  }

  depends_on = [
    libvirt_volume.node_root,
    libvirt_volume.node_cloudinit,
  ]
}

# ============================================================
# 5. Talos cluster bootstrapping (module)
# ============================================================

module "talos" {
  source = "../modules/talos-cluster"

  cp_ips             = local.cp_ips
  cp_hostnames       = local.cp_hostnames
  worker_ips         = local.worker_ips
  worker_hostnames   = local.worker_hostnames
  cluster_vip        = var.cluster_vip
  talos_version      = var.talos_version
  talos_image_id     = var.talos_image_factory_id
  tailscale_domain   = var.tailscale_domain
  tailscale_auth_key = var.tailscale_auth_key

  depends_on = [
    libvirt_domain.node
  ]
}
