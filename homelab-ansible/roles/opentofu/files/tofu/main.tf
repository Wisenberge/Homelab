# Managed by Ansible (role: opentofu).
# Values come from homelab.auto.tfvars.json, which Ansible writes from the
# opentofu_* variables. Change those variables, not this file.

# Download the cloud image onto the Proxmox node once. Every VM is built from it.
resource "proxmox_virtual_environment_download_file" "cloud_image" {
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node
  url          = var.cloud_image_url
  file_name    = var.cloud_image_file_name
}

locals {
  # Turn the VM list into a map keyed by name, so each VM is tracked by its
  # name and reordering the list never rebuilds anything.
  vms = { for vm in var.vms : vm.name => vm }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms

  name        = each.key
  description = "Managed by OpenTofu (homelab)"
  node_name   = var.proxmox_node
  vm_id       = each.value.vm_id
  tags        = sort(distinct(concat(["opentofu"], each.value.tags)))
  started     = each.value.started
  on_boot     = each.value.on_boot

  # Without the guest agent, shutdown requests can be ignored; force it off.
  stop_on_destroy = true

  agent {
    enabled = var.guest_agent
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  disk {
    datastore_id = var.vm_datastore
    import_from  = proxmox_virtual_environment_download_file.cloud_image.id
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = each.value.disk_gb
  }

  network_device {
    bridge  = var.network_bridge
    vlan_id = each.value.vlan_id
  }

  operating_system {
    type = "l26" # Linux
  }

  # Cloud images expect a serial console.
  serial_device {}

  # Cloud-init: network, DNS and login.
  initialization {
    datastore_id = var.vm_datastore

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.ip == "dhcp" ? null : var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.vm_user
      keys     = var.ssh_public_keys
    }
  }
}
