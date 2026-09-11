variable "talos_version" {
  description = "Talos Linux version (e.g. 1.14.0)"
  type        = string

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version must be semver X.Y.Z (e.g. 1.14.0)."
  }
}

variable "platform" {
  description = "Image Factory platform for download/installer URLs (e.g. nocloud, metal)"
  type        = string
  default     = "nocloud"
}

variable "architecture" {
  description = "Image Factory architecture for download/installer URLs"
  type        = string
  default     = "amd64"
}

variable "extensions" {
  description = "Canonical extension list (full siderolabs/<name> for exact_filters); single source of truth for the schematic."
  type        = list(string)
  default = [
    "siderolabs/iscsi-tools",
    "siderolabs/qemu-guest-agent",
    "siderolabs/util-linux-tools",
  ]
}
