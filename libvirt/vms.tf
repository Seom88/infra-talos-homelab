# ============================================================
# Locals & Node Mapping
# ============================================================

locals {
  nodes_all = merge(
    { for n in var.nodes_cp : n.hostname => {
      role      = "cp"
      mac       = n.mac
      ip        = n.ip
      cores     = n.cores
      memory    = n.memory
      disk_size = n.disk_size
      pool      = coalesce(n.pool, libvirt_pool.talos.name)
    } },
    { for n in var.nodes_worker : n.hostname => {
      role      = "worker"
      mac       = n.mac
      ip        = n.ip
      cores     = n.cores
      memory    = n.memory
      disk_size = n.disk_size
      pool      = coalesce(n.pool, libvirt_pool.talos.name)
    } },
  )
}

# ============================================================
# Boot Volumes (Bootstrap Only)
# ============================================================

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

# Workaround for dmacvicar/libvirt capacity with raw images
resource "terraform_data" "resize_boot" {
  for_each = local.nodes_all

  triggers_replace = "${each.key}-${each.value.disk_size}-${libvirt_volume.boot[each.key].id}"

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

# ============================================================
# Cloud-init — network-config + Talos machine config (user-data)
# ============================================================

resource "libvirt_cloudinit_disk" "cloud_init" {
  for_each = local.nodes_all
  name     = "${each.key}-cloudinit.iso"

  meta_data = yamlencode({
    instance-id    = each.key
    local-hostname = each.key
  })

  network_config = yamlencode({
    version = 1
    config = [{
      type        = "physical"
      name        = "eth0"
      mac_address = each.value.mac
      subnets = [{
        type    = "static"
        address = "${each.value.ip}/${var.network_prefix}"
        gateway = var.gateway
      }]
    }]
  })

  user_data = each.value.role == "cp" ? data.talos_machine_configuration.cp.machine_configuration : data.talos_machine_configuration.worker.machine_configuration
}

resource "libvirt_volume" "cloud_init" {
  for_each = local.nodes_all
  name     = "${each.key}-cloudinit.iso"
  pool     = each.value.pool

  create = {
    content = {
      url = libvirt_cloudinit_disk.cloud_init[each.key].path
    }
  }
}

# ============================================================
# VM Domains (UEFI OVMF with custom code & vars template)
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

    disks = [
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
      {
        device   = "cdrom"
        readonly = true
        source = {
          volume = {
            pool   = libvirt_volume.cloud_init[each.key].pool
            volume = libvirt_volume.cloud_init[each.key].name
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      },
    ]

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
    libvirt_volume.cloud_init,
    terraform_data.resize_boot,
  ]
}
