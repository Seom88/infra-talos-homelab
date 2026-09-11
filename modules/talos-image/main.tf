# Canonical Image Factory wiring: extensions data -> schematic publisher -> download/installer URLs.
# Single source of truth for the extension set; no YAML files, no manual URL interpolation.

data "talos_image_factory_extensions_versions" "this" {
  talos_version = "v${var.talos_version}"
  exact_filters = {
    # NOTE: exact match requires full "siderolabs/<name>"; short names resolve to null.
    names = var.extensions
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [for e in data.talos_image_factory_extensions_versions.this.extensions_info : e.name]
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = "v${var.talos_version}"
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = var.platform
  architecture  = var.architecture
}
