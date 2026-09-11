output "schematic_id" {
  description = "Image Factory schematic ID for the canonical extension set"
  value       = talos_image_factory_schematic.this.id
}

output "installer_image" {
  description = "Installer reference for talos_machine.image (plain flavor)"
  value       = data.talos_image_factory_urls.this.urls.installer
}

output "installer_image_secureboot" {
  description = "Installer reference for talos_machine.image (secureboot flavor)"
  value       = data.talos_image_factory_urls.this.urls.installer_secureboot
}

output "disk_image_url" {
  description = "Download URL for the nocloud raw.xz disk image (plain flavor)"
  value       = data.talos_image_factory_urls.this.urls.disk_image
}

output "disk_image_secureboot_url" {
  description = "Download URL for the nocloud raw.xz disk image (secureboot flavor)"
  value       = data.talos_image_factory_urls.this.urls.disk_image_secureboot
}
