# Managed by Ansible (role: opentofu).

output "vms" {
  description = "Every VM OpenTofu manages, with its Proxmox ID and configured IP"
  value = {
    for name, vm in proxmox_virtual_environment_vm.vm : name => {
      vm_id = vm.vm_id
      ip    = local.vms[name].ip
    }
  }
}
