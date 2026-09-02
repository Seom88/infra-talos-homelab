# Talos schematic and base volume (bootstrap only)

resource "talos_image_factory_schematic" "this" {
  schematic = file(var.schematic_path)
}

locals {
  image_cache_dir = replace(var.talos_image_cache_dir, "/^~/", pathexpand("~"))
  # Fixed name so version bumps don't wipe disks
  image_filename    = var.secureboot ? "talos-nocloud-amd64-secureboot.raw" : "talos-nocloud-amd64.raw"
  cached_raw_path   = "${local.image_cache_dir}/${local.image_filename}"
  cached_qcow2_path = "${local.image_cache_dir}/${replace(local.image_filename, ".raw", ".qcow2")}"
}

# Base volume - qcow2 thin provisioned for homelab trial (provider converts raw cache -> qcow2 on upload)
resource "libvirt_volume" "talos_base_image" {
  name = var.secureboot ? "talos-base-secureboot.qcow2" : "talos-base.qcow2"
  pool = libvirt_pool.talos.name

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
    libvirt_pool.talos,
    terraform_data.talos_nocloud_image,
  ]
}

# Image cache: re-downloads on version/schematic change; sidecar invalidates stale cache.
resource "terraform_data" "talos_nocloud_image" {
  triggers_replace = {
    secureboot    = var.secureboot
    cache_dir     = local.image_cache_dir
    talos_version = var.talos_version
    schematic_id  = talos_image_factory_schematic.this.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      CACHE_DIR="${local.image_cache_dir}"
      SCHEMATIC_ID="${talos_image_factory_schematic.this.id}"
      RAW_PATH="${local.cached_raw_path}"
      QCOW2_PATH="${local.cached_qcow2_path}"
      IMAGE_TYPE="${var.secureboot ? "nocloud-amd64-secureboot.raw.xz" : "nocloud-amd64.raw.xz"}"
      MARKER_FILE="$${CACHE_DIR}/.schematic-$${SCHEMATIC_ID}-v${var.talos_version}"
      mkdir -p "$${CACHE_DIR}"

      if [ -f "$${RAW_PATH}" ] && [ -f "$${QCOW2_PATH}" ] && [ -f "$${MARKER_FILE}" ]; then
        echo "Bootstrap image already cached for $${SCHEMATIC_ID} v${var.talos_version}: $${RAW_PATH} + $${QCOW2_PATH}"
        chmod 644 "$${RAW_PATH}" "$${QCOW2_PATH}" || true
        exit 0
      fi

      if [ ! -f "$${RAW_PATH}" ] || [ ! -f "$${MARKER_FILE}" ]; then
        echo "Downloading Talos nocloud image $${SCHEMATIC_ID} v${var.talos_version} ($${IMAGE_TYPE})..."
        curl -fsSL "https://factory.talos.dev/image/$${SCHEMATIC_ID}/v${var.talos_version}/$${IMAGE_TYPE}" \
          | xz -d > "$${RAW_PATH}.tmp"

        chmod 644 "$${RAW_PATH}.tmp" || true
        mv "$${RAW_PATH}.tmp" "$${RAW_PATH}"
        # Mark as cached
        rm -f "$${CACHE_DIR}/.schematic-"* 2>/dev/null || true
        touch "$${MARKER_FILE}"
        echo "Cached raw: $${RAW_PATH} ($${SCHEMATIC_ID} v${var.talos_version})"
      fi

      # Convert raw -> qcow2 for dir pool (libvirt dir pool does not auto-convert)
      if ! command -v qemu-img >/dev/null 2>&1; then
        echo "ERROR: qemu-img not found (qemu-utils/qemu-img package required for raw->qcow2 conversion)" >&2
        exit 1
      fi

      if [ ! -f "$${QCOW2_PATH}" ] || [ "$${RAW_PATH}" -nt "$${QCOW2_PATH}" ]; then
        echo "Converting raw -> qcow2: $${RAW_PATH} -> $${QCOW2_PATH}"
        qemu-img convert -p -f raw -O qcow2 "$${RAW_PATH}" "$${QCOW2_PATH}.tmp"
        chmod 644 "$${QCOW2_PATH}.tmp" || true
        mv "$${QCOW2_PATH}.tmp" "$${QCOW2_PATH}"
        touch "$${MARKER_FILE}"
      fi

      echo "Cached: $${RAW_PATH} + $${QCOW2_PATH} ($${SCHEMATIC_ID} v${var.talos_version})"
      qemu-img info "$${QCOW2_PATH}" || true
    EOT
  }

  depends_on = [libvirt_pool.talos]
}
