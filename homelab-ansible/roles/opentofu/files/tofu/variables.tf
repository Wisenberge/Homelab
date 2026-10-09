# Managed by Ansible (role: opentofu).

variable "proxmox_endpoint" {
  description = "Proxmox URL, e.g. https://192.168.1.10:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token: user@realm!tokenname=uuid (passed in via the .env file)"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (Proxmox's default certificate is self-signed)"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node that runs the VMs"
  type        = string
}

variable "image_datastore" {
  description = "Storage for the downloaded cloud image (needs the Import content type)"
  type        = string
  default     = "local"
}

variable "vm_datastore" {
  description = "Storage for VM disks and cloud-init drives"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "gateway" {
  description = "Default gateway for VMs with a static IP"
  type        = string
}

variable "dns_servers" {
  type    = list(string)
  default = []
}

variable "cloud_image_url" {
  type = string
}

variable "cloud_image_file_name" {
  description = "Name to save the image as; must end in .qcow2"
  type        = string

  validation {
    condition     = endswith(var.cloud_image_file_name, ".qcow2")
    error_message = "cloud_image_file_name must end in .qcow2."
  }
}

variable "vm_user" {
  type    = string
  default = "homelab"
}

variable "ssh_public_keys" {
  type    = list(string)
  default = []
}

variable "guest_agent" {
  description = "Enable only if the image has qemu-guest-agent installed"
  type        = bool
  default     = false
}

variable "vms" {
  description = "The VMs to create"
  type = list(object({
    name      = string
    vm_id     = optional(number)
    cores     = optional(number, 2)
    memory_mb = optional(number, 2048)
    disk_gb   = optional(number, 20)
    ip        = optional(string, "dhcp")
    vlan_id   = optional(number)
    tags      = optional(list(string), [])
    started   = optional(bool, true)
    on_boot   = optional(bool, true)
  }))
  default = []

  validation {
    condition     = alltrue([for vm in var.vms : vm.ip == "dhcp" || can(cidrhost(vm.ip, 0))])
    error_message = "Each VM's ip must be \"dhcp\" or an address with a prefix, like 192.168.1.21/24."
  }
}
