# Talos schematic and base volume (bootstrap only)

resource "talos_image_factory_schematic" "this" {
  schematic = file(var.schematic_path)
}

locals {
  image_cache_dir = replace(var.talos_image_cache_dir, "/^~/", pathexpand("~"))
  # Fixed name so version bumps don't wipe disks
  image_filename  = var.secureboot ? "talos-nocloud-amd64-secureboot.raw" : "talos-nocloud-amd64.raw"
  cached_raw_path = "${local.image_cache_dir}/${local.image_filename}"
}

# Base volume
resource "libvirt_volume" "talos_base_image" {
  name = var.secureboot ? "talos-base-secureboot.raw" : "talos-base.raw"
  pool = libvirt_pool.talos.name

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
      IMAGE_TYPE="${var.secureboot ? "nocloud-amd64-secureboot.raw.xz" : "nocloud-amd64.raw.xz"}"
      MARKER_FILE="$${CACHE_DIR}/.schematic-$${SCHEMATIC_ID}-v${var.talos_version}"
      mkdir -p "$${CACHE_DIR}"

      if [ -f "$${RAW_PATH}" ] && [ -f "$${MARKER_FILE}" ]; then
        echo "Bootstrap image already cached for $${SCHEMATIC_ID} v${var.talos_version}: $${RAW_PATH}"
        chmod 644 "$${RAW_PATH}" || true
        exit 0
      fi

      echo "Downloading Talos nocloud image $${SCHEMATIC_ID} v${var.talos_version} ($${IMAGE_TYPE})..."
      curl -fsSL "https://factory.talos.dev/image/$${SCHEMATIC_ID}/v${var.talos_version}/$${IMAGE_TYPE}" \
        | xz -d > "$${RAW_PATH}.tmp"

      chmod 644 "$${RAW_PATH}.tmp" || true
      mv "$${RAW_PATH}.tmp" "$${RAW_PATH}"
      # Mark as cached
      rm -f "$${CACHE_DIR}/.schematic-"* 2>/dev/null || true
      touch "$${MARKER_FILE}"
      echo "Cached: $${RAW_PATH} ($${SCHEMATIC_ID} v${var.talos_version})"
    EOT
  }

  depends_on = [libvirt_pool.talos]
}
