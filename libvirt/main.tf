# ============================================================
# Talos Schematic
# ============================================================

resource "talos_image_factory_schematic" "this" {
  schematic = file("${path.module}/../schematic-${var.env_name}.yaml")
}

# ============================================================
# Locals
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

  cp_ips           = [for n in var.nodes_cp : n.ip]
  worker_ips       = [for n in var.nodes_worker : n.ip]
  all_ips          = concat(local.cp_ips, local.worker_ips)
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  netmask          = cidrnetmask("${local.cp_ips[0]}/${var.network_prefix}")

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
# Talos Machine Secrets
# ============================================================

resource "talos_machine_secrets" "this" {
  talos_version = "v${var.talos_version}"
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.cp_ips
  nodes                = local.all_ips
}

# ============================================================
# Control Plane machine config
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
          var.tailscale_domain != "" ? [for n in var.nodes_cp : "${n.hostname}.${var.tailscale_domain}"] : []
        )
        install = {
          disk  = "/dev/vda"
          image = "factory.talos.dev/nocloud-installer/${talos_image_factory_schematic.this.id}:v${var.talos_version}"
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

# ============================================================
# Worker machine config
# ============================================================

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
        certSANs = var.tailscale_domain != "" ? [for n in var.nodes_worker : "${n.hostname}.${var.tailscale_domain}"] : []
        install = {
          disk  = "/dev/vda"
          image = "factory.talos.dev/nocloud-installer/${talos_image_factory_schematic.this.id}:v${var.talos_version}"
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
# Cidata ISO — per node: meta-data, network-config, user-data
# ============================================================

resource "terraform_data" "cidata_iso" {
  for_each = local.nodes_all

  triggers_replace = {
    network       = "${each.value.ip}/${each.value.mac}/${var.gateway}/${var.network_prefix}"
    role          = each.value.role
    talos_version = var.talos_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      IDIR="/tmp/cidata-${each.key}"
      mkdir -p "$${IDIR}"

      cat > "$${IDIR}/meta-data" << 'METAEOF'
instance-id: "${each.key}"
local-hostname: ${each.key}
METAEOF

      cat > "$${IDIR}/network-config" << NETEOF
version: 1
config:
  - type: physical
    name: eth0
    mac_address: "${each.value.mac}"
    subnets:
      - type: static
        address: "${each.value.ip}"
        netmask: "${local.netmask}"
        gateway: "${var.gateway}"
NETEOF

      printf '%s\n' "$USER_DATA" > "$${IDIR}/user-data"

      rm -f /tmp/cidata-${each.key}.iso
      genisoimage -quiet -output /tmp/cidata-${each.key}.iso \
        -V cidata -r -J \
        "$${IDIR}/meta-data" \
        "$${IDIR}/network-config" \
        "$${IDIR}/user-data"
    EOT

    environment = {
      USER_DATA = each.value.role == "cp" ? data.talos_machine_configuration.cp.machine_configuration : data.talos_machine_configuration.worker.machine_configuration
    }
  }

  depends_on = [
    data.talos_machine_configuration.cp,
    data.talos_machine_configuration.worker,
  ]
}

# ============================================================
# Cidata ISO volumes
# ============================================================

resource "libvirt_volume" "cidata" {
  for_each = local.nodes_all
  name     = "${each.key}-cidata.iso"
  pool     = "default"

  create = {
    content = {
      url = "file:///tmp/cidata-${each.key}.iso"
    }
  }

  depends_on = [terraform_data.cidata_iso]
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
            pool   = libvirt_volume.cidata[each.key].pool
            volume = libvirt_volume.cidata[each.key].name
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
            network = "default"
          }
        }
      },
    ]
  }

  depends_on = [
    libvirt_volume.boot,
    libvirt_volume.cidata,
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
# Bootstrap etcd
# ============================================================

resource "talos_machine_bootstrap" "this" {
  depends_on = [
    terraform_data.wait_for_cp,
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ips[0]
  endpoint             = local.cp_ips[0]
}

# ============================================================
# Kubeconfig
# ============================================================

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this,
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.cp_ips[0]
}
