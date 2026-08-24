# ============================================================
# Talos Schematic & Base Template Volume (Bootstrap Only)
# ============================================================

resource "talos_image_factory_schematic" "this" {
  schematic = file("${path.module}/../${var.schematic_name}")
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

# Image downloader: bootstrap-only cache (does not re-download on talos_version bump)
resource "terraform_data" "talos_nocloud_image" {
  # Only recreate if secureboot mode or cache dir path changes
  triggers_replace = "${var.secureboot}-${local.image_cache_dir}"

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      CACHE_DIR="${local.image_cache_dir}"
      SCHEMATIC_ID="${talos_image_factory_schematic.this.id}"
      RAW_PATH="${local.cached_raw_path}"
      IMAGE_TYPE="${var.secureboot ? "nocloud-amd64-secureboot.raw.xz" : "nocloud-amd64.raw.xz"}"
      mkdir -p "$${CACHE_DIR}"

      if [ -f "$${RAW_PATH}" ]; then
        echo "Bootstrap image already cached: $${RAW_PATH}"
        chmod 644 "$${RAW_PATH}" || true
        exit 0
      fi

      curl -fsSL "https://factory.talos.dev/image/$${SCHEMATIC_ID}/v${var.talos_version}/$${IMAGE_TYPE}" \
        | xz -d > "$${RAW_PATH}"

      chmod 644 "$${RAW_PATH}" || true
    EOT
  }

  depends_on = [libvirt_pool.talos]
}
