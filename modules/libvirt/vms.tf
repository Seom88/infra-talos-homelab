# Node mapping with deterministic MACs
# Data disk resolution: per-disk pool > default_data_pool > per-node pool > default_pool > managed pool.

locals {
  data_device_letters = ["vdb", "vdc", "vdd", "vde", "vdf", "vdg", "vdh", "vdi", "vdj", "vdk"]

  nodes_all = merge(
    { for n in var.nodes_cp : n.hostname => {
      role      = "cp"
      mac       = coalesce(n.mac, format("52:54:00:%s:%s:%s", substr(md5(n.hostname), 0, 2), substr(md5(n.hostname), 2, 2), substr(md5(n.hostname), 4, 2)))
      ip        = n.ip
      cores     = n.cores
      memory    = n.memory
      disk_size = n.disk_size
      pool      = coalesce(n.pool, var.default_pool, libvirt_pool.talos.name)
      effective_disks = [
        for d in coalesce(n.disks, []) : {
          name = d.name
          size = d.size
          pool = coalesce(d.pool, var.default_data_pool, n.pool, var.default_pool, libvirt_pool.talos.name)
        }
      ]
    } },
    { for n in var.nodes_worker : n.hostname => {
      role      = "worker"
      mac       = coalesce(n.mac, format("52:54:00:%s:%s:%s", substr(md5(n.hostname), 0, 2), substr(md5(n.hostname), 2, 2), substr(md5(n.hostname), 4, 2)))
      ip        = n.ip
      cores     = n.cores
      memory    = n.memory
      disk_size = n.disk_size
      pool      = coalesce(n.pool, var.default_pool, libvirt_pool.talos.name)
      effective_disks = [
        for d in coalesce(n.disks, []) : {
          name = d.name
          size = d.size
          pool = coalesce(d.pool, var.default_data_pool, n.pool, var.default_pool, libvirt_pool.talos.name)
        }
      ]
    } },
  )

  data_volumes = {
    for entry in flatten([
      for hostname, node in local.nodes_all : [
        for d in node.effective_disks : {
          key      = "${hostname}-${d.name}"
          hostname = hostname
          disk     = d
        }
      ]
    ]) : entry.key => entry
  }
}

# Boot volumes (bootstrap only)

resource "libvirt_volume" "boot" {
  for_each = local.nodes_all
  name     = "${each.key}.qcow2"
  pool     = each.value.pool
  capacity = each.value.disk_size * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = "file://${local.cached_qcow2_path}"
    }
  }

  lifecycle {
    ignore_changes = [create]
  }

  depends_on = [
    libvirt_volume.talos_base_image,
  ]
}

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
      VOL="${each.key}.qcow2"
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

# Data volumes (scalable extra disks, vdb and up)

resource "libvirt_volume" "data" {
  for_each = local.data_volumes
  name     = "${each.value.hostname}-${each.value.disk.name}.qcow2"
  pool     = each.value.disk.pool
  capacity = each.value.disk.size * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }

  depends_on = [libvirt_pool.talos]
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
          driver = {
            name = "qemu"
            type = "qcow2"
          }
        },
      ],
      [
        for idx, d in local.nodes_all[each.key].effective_disks : {
          source = {
            volume = {
              pool   = libvirt_volume.data["${each.key}-${d.name}"].pool
              volume = libvirt_volume.data["${each.key}-${d.name}"].name
            }
          }
          target = {
            dev = local.data_device_letters[idx]
            bus = "virtio"
          }
          driver = {
            name = "qemu"
            type = "qcow2"
          }
        }
      ]
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
