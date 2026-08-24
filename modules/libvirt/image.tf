# ============================================================
# Talos Schematic & Base Template Volume (Bootstrap Only)
# ============================================================

resource "talos_image_factory_schematic" "this" {
  schematic = file(var.schematic_path)
}

locals {
  image_cache_dir = replace(var.talos_image_cache_dir, "/^~/", pathexpand("~"))
  # Stable fixed name for bootstrap image so version bumps don't wipe disks
  image_filename  = var.secureboot ? "talos-nocloud-amd64-secureboot.raw" : "talos-nocloud-amd64.raw"
  cached_raw_path = "${local.image_cache_dir}/${local.image_filename}"
}

# Base volume in the dedicated Talos pool
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

# Image downloader: version/schematic-aware cache
# Re-downloads only when talos_version or schematic changes (via triggers_replace).
# Uses a sidecar file to track which schematic produced the cached raw, so stale
# cache (e.g. old schematic with same filename) is correctly invalidated and
# talos_machine.image does not trigger a spurious upgrade on fresh bootstrap.
resource "terraform_data" "talos_nocloud_image" {
  triggers_replace = "${var.secureboot}-${local.image_cache_dir}-${var.talos_version}-${talos_image_factory_schematic.this.id}"

  provisioner "local-exec" {
    command = <<-EOT
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
      # Mark this schematic/version as cached (clean old markers)
      rm -f "$${CACHE_DIR}/.schematic-"* 2>/dev/null || true
      touch "$${MARKER_FILE}"
      echo "Cached: $${RAW_PATH} ($${SCHEMATIC_ID} v${var.talos_version})"
    EOT
  }

  depends_on = [libvirt_pool.talos]
}
