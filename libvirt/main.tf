# ============================================================
# Libvirt Network — NAT with DHCP reservations for Talos nodes
# ============================================================

resource "libvirt_network" "talos" {
  name      = "talos-net"
  autostart = true

  forward = { mode = "nat" }

  bridge = {
    name = "virbr-talos"
    stp  = "on"
  }

  ips = [
    {
      address = "10.0.1.1"
      netmask = "255.255.255.0"
      dhcp = {
        hosts = [
          for n in concat(var.nodes_cp, var.nodes_worker) : {
            mac  = n.mac
            name = n.hostname
            ip   = n.ip
          }
        ]
      }
    }
  ]

  dns = {
    enable = "yes"
    host = [
      for n in concat(var.nodes_cp, var.nodes_worker) : {
        ip = n.ip
        hostnames = [{ hostname = n.hostname }]
      }
    ]
  }
}

# ============================================================
# Talos Schematic
# ============================================================

resource "talos_image_factory_schematic" "this" {
  schematic = file("${path.module}/../schematic-${var.env_name}.yaml")
}

# ============================================================
# Talos Machine Secrets (shared with module)
# ============================================================

resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"
}

# ============================================================
# Locals — libvirt-specific + Talos patches
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
    } },
    { for n in var.nodes_worker : n.hostname => {
      role      = "worker"
      mac       = n.mac
      ip        = n.ip
      cores     = n.cores
      memory    = n.memory
      disk_size = n.disk_size
    } },
  )

  cp_ips  = [for n in var.nodes_cp : n.ip]
  netmask = cidrnetmask("${local.cp_ips[0]}/${var.network_prefix}")

  cluster_endpoint = "https://${var.cluster_vip}:6443"
  install_image    = "factory.talos.dev/nocloud-installer/${talos_image_factory_schematic.this.id}:v${var.talos_version}"

  tailscale_cp_names     = var.tailscale_domain != "" ? [for n in var.nodes_cp : "${n.hostname}.${var.tailscale_domain}"] : []
  tailscale_worker_names = var.tailscale_domain != "" ? [for n in var.nodes_worker : "${n.hostname}.${var.tailscale_domain}"] : []

  dns_patch = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "ResolverConfig"
    nameservers = var.tailscale_auth_key != "" ? [
      { address = "100.100.100.100" },
      ] : [
      { address = "1.1.1.1" },
      { address = "1.0.0.1" },
    ]
  })

  longhorn_patch = var.longhorn_enabled ? yamlencode({
    machine = {
      kubelet = {
        extraMounts = [
          {
            destination = "/var/lib/longhorn"
            type        = "bind"
            source      = "/var/lib/longhorn"
            options     = ["bind", "rshared", "rw"]
          }
        ]
      }
    }
  }) : ""

  tailscale_patch = var.tailscale_auth_key != "" ? yamlencode({
    apiVersion = "v1alpha1"
    kind       = "ExtensionServiceConfig"
    name       = "tailscale"
    environment = [
      "TS_AUTHKEY=${var.tailscale_auth_key}",
      "TS_ACCEPT_DNS=false"
    ]
  }) : ""
}

# ============================================================
# Talos Machine Configuration — for cloud-init user-data
# ============================================================

data "talos_machine_configuration" "cp" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = "v${var.kubernetes_version}"
  talos_version      = "v${var.talos_version}"
  config_patches = compact(concat([
    yamlencode({
      machine = {
        certSANs = concat(
          local.cp_ips,
          local.tailscale_cp_names,
        )
        install = {
          disk  = "/dev/vda"
          image = local.install_image
        }
      }
    }),
    var.allow_scheduling_on_control_planes ? yamlencode({
      cluster = {
        allowSchedulingOnControlPlanes = true
      }
    }) : "",
    local.dns_patch,
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "Layer2VIPConfig"
      name       = var.cluster_vip
      link       = "eth0"
    }),
    local.tailscale_patch,
    local.longhorn_patch,
  ], var.extra_config_patches))
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = "v${var.kubernetes_version}"
  talos_version      = "v${var.talos_version}"
  config_patches = compact(concat([
    yamlencode({
      machine = {
        certSANs = local.tailscale_worker_names
        install = {
          disk  = "/dev/vda"
          image = local.install_image
        }
      }
    }),
    local.dns_patch,
    local.tailscale_patch,
    local.longhorn_patch,
  ], var.extra_config_patches))
}

# ============================================================
# Nocloud disk image — download + decompress
# ============================================================

resource "terraform_data" "talos_nocloud_image" {
  triggers_replace = var.talos_version

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      CACHE_DIR="${var.talos_image_cache_dir}"
      RAW_PATH="$${CACHE_DIR}/talos-nocloud-v${var.talos_version}.raw"
      mkdir -p "$${CACHE_DIR}"

      if [ -f "$${RAW_PATH}" ]; then
        echo "Image already cached: $${RAW_PATH}"
        exit 0
      fi

      curl -fsSL "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/v${var.talos_version}/nocloud-amd64.raw.xz" \
        | xz -d > "$${RAW_PATH}"
    EOT
  }
}

# ============================================================
# Boot volumes — one per node from the nocloud raw image
# ============================================================

resource "libvirt_volume" "boot" {
  for_each = local.nodes_all
  name     = "${each.key}.raw"
  pool     = "default"

  target = {
    format = {
      type = "raw"
    }
  }

  create = {
    content = {
      url = "file://${var.talos_image_cache_dir}/talos-nocloud-v${var.talos_version}.raw"
    }
  }

  depends_on = [terraform_data.talos_nocloud_image]
}

# ============================================================
# Cloud-init — network-config + Talos machine config (user-data)
# ============================================================

resource "libvirt_cloudinit_disk" "cloud_init" {
  for_each = local.nodes_all
  name     = "${each.key}-cloudinit"

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
        address = "${each.value.ip}/${local.netmask}"
        gateway = var.gateway
      }]
    }]
  })

  user_data = each.value.role == "cp" ? data.talos_machine_configuration.cp.machine_configuration : data.talos_machine_configuration.worker.machine_configuration
}

resource "libvirt_volume" "cloud_init" {
  for_each = local.nodes_all
  name     = "${each.key}-cloudinit.iso"
  pool     = "default"

  create = {
    content = {
      url = libvirt_cloudinit_disk.cloud_init[each.key].path
    }
  }
}

# ============================================================
# VM Domains
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
    boot_devices = [
      { dev = "hd" },
    ]
  }

  devices = {
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
  ]
}

# ============================================================
# Wait for first control plane Talos API
# ============================================================

resource "terraform_data" "wait_for_cp" {
  provisioner "local-exec" {
    command = <<-EOT
      IP="${var.nodes_cp[0].ip}"
      echo "Waiting for ${var.nodes_cp[0].hostname} ($${IP})..."
      for i in $(seq 1 30); do
        if timeout 3 bash -c "echo > /dev/tcp/$${IP}/50000" 2>/dev/null \
           || timeout 3 bash -c "echo > /dev/tcp/$${IP}/6443" 2>/dev/null; then
          exit 0
        fi
        sleep 10
      done
      exit 1
    EOT
  }

  depends_on = [libvirt_domain.node]
}

# ============================================================
# Talos Cluster — apply, bootstrap, kubeconfig
# ============================================================

module "talos_cluster" {
  source = "../modules/talos-cluster"

  machine_secrets                    = talos_machine_secrets.this.machine_secrets
  client_configuration               = talos_machine_secrets.this.client_configuration
  cp_ips                             = local.cp_ips
  cp_hostnames                       = [for n in var.nodes_cp : n.hostname]
  worker_ips                         = [for n in var.nodes_worker : n.ip]
  worker_hostnames                   = [for n in var.nodes_worker : n.hostname]
  cluster_name                       = var.cluster_name
  cluster_vip                        = var.cluster_vip
  talos_version                      = var.talos_version
  kubernetes_version                 = var.kubernetes_version
  talos_image_id                     = talos_image_factory_schematic.this.id
  tailscale_domain                   = var.tailscale_domain
  tailscale_auth_key                 = var.tailscale_auth_key
  allow_scheduling_on_control_planes = var.allow_scheduling_on_control_planes
  longhorn_enabled                   = var.longhorn_enabled
  extra_config_patches               = var.extra_config_patches

  depends_on = [
    terraform_data.wait_for_cp,
  ]
}
