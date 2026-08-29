# Node mapping with deterministic MACs

locals {
  nodes_all = merge(
    { for n in var.nodes_cp : n.hostname => {
      role           = "cp"
      mac            = coalesce(n.mac, format("52:54:00:%s:%s:%s", substr(md5(n.hostname), 0, 2), substr(md5(n.hostname), 2, 2), substr(md5(n.hostname), 4, 2)))
      ip             = n.ip
      cores          = n.cores
      memory         = n.memory
      disk_size      = n.disk_size
      pool           = coalesce(n.pool, libvirt_pool.talos.name)
      data_disk_size = try(n.data_disk_size, null)
      data_pool      = coalesce(try(n.data_pool, null), try(n.pool, null), libvirt_pool.talos.name)
    } },
    { for n in var.nodes_worker : n.hostname => {
      role           = "worker"
      mac            = coalesce(n.mac, format("52:54:00:%s:%s:%s", substr(md5(n.hostname), 0, 2), substr(md5(n.hostname), 2, 2), substr(md5(n.hostname), 4, 2)))
      ip             = n.ip
      cores          = n.cores
      memory         = n.memory
      disk_size      = n.disk_size
      pool           = coalesce(n.pool, libvirt_pool.talos.name)
      data_disk_size = try(n.data_disk_size, null)
      data_pool      = coalesce(try(n.data_pool, null), try(n.pool, null), libvirt_pool.talos.name)
    } },
  )
}

# Boot volumes (bootstrap only)

resource "libvirt_volume" "boot" {
  for_each = local.nodes_all
  name     = "${each.key}.raw"
  pool     = each.value.pool
  capacity = each.value.disk_size * 1024 * 1024 * 1024

  target = {
    format = {
      type = "raw"
    }
  }

  create = {
    content = {
      url = "file://${local.cached_raw_path}"
    }
  }

  lifecycle {
    ignore_changes = [create]
  }

  depends_on = [
    libvirt_volume.talos_base_image,
  ]
}

# Resize boot volumes for raw images (dmacvicar/libvirt workaround)
resource "terraform_data" "resize_boot" {
  for_each = local.nodes_all

  triggers_replace = {
    node      = each.key
    disk_size = each.value.disk_size
    volume_id = libvirt_volume.boot[each.key].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      VOL="${each.key}.raw"
      POOL="${each.value.pool}"
      WANT_GB="${each.value.disk_size}"
      CUR_BYTES=$(virsh --connect qemu:///system vol-dumpxml --pool "$POOL" "$VOL" 2>/dev/null | sed -n "s/.*<capacity unit='bytes'>\([0-9]*\)<\/capacity>.*/\1/p")
      WANT_BYTES=$(( WANT_GB * 1024 * 1024 * 1024 ))
      if [ -z "$CUR_BYTES" ]; then
        echo "resize_boot: could not read $POOL/$VOL, skipping"
        exit 0
      fi
      if [ "$CUR_BYTES" -ge "$WANT_BYTES" ]; then
        echo "resize_boot: $POOL/$VOL already $CUR_BYTES >= $WANT_BYTES, skip"
        exit 0
      fi
      echo "resize_boot: resizing $POOL/$VOL from $CUR_BYTES to $WANT_BYTES ($WANT_GB GiB)"
      virsh --connect qemu:///system vol-resize --pool "$POOL" "$VOL" "$${WANT_GB}G"
    EOT
  }

  depends_on = [libvirt_volume.boot]
}

# Data volumes (optional second disk)

resource "libvirt_volume" "data" {
  for_each = { for k, v in local.nodes_all : k => v if try(v.data_disk_size, null) != null }
  name     = "${each.key}-data.raw"
  pool     = each.value.data_pool
  capacity = each.value.data_disk_size * 1024 * 1024 * 1024

  target = {
    format = {
      type = "raw"
    }
  }
}

# VM domains (UEFI OVMF)

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
    loader       = var.secureboot ? var.ovmf_code_secboot : null
    nvram = var.secureboot ? {
      template = var.ovmf_vars_secboot
    } : null
    boot_devices = [
      { dev = "hd" },
    ]
  }

  devices = {
    channels = [
      {
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
          }
        }
      },
    ]

    consoles = [
      {
        type = "pty"
        target = {
          type = "serial"
          port = 0
        }
      },
    ]

    disks = concat(
      [
        {
          source = {
            volume = {
              pool   = libvirt_volume.boot[each.key].pool
              volume = libvirt_volume.boot[each.key].name
            }
          }
          target = {
            dev = "vda"
            bus = "virtio"
          }
        },
      ],
      try(local.nodes_all[each.key].data_disk_size, null) != null ? [
        {
          source = {
            volume = {
              pool   = libvirt_volume.data[each.key].pool
              volume = libvirt_volume.data[each.key].name
            }
          }
          target = {
            dev = "vdb"
            bus = "virtio"
          }
        },
      ] : []
    )

    graphics = [
      {
        vnc = {
          autoport = true
          listen   = "127.0.0.1"
        }
      },
    ]

    interfaces = [
      {
        mac   = { address = each.value.mac }
        model = { type = "virtio" }
        source = {
          network = {
            network = libvirt_network.talos.name
          }
        }
      },
    ]
  }

  depends_on = [
    libvirt_volume.boot,
    libvirt_volume.data,
    terraform_data.resize_boot,
  ]
}
