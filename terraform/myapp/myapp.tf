provider "vault" {
    skip_tls_verify = true
}

data "vault_generic_secret" "vmware" {
    path ="secrets/vmware"
}

provider "vsphere" {
    user = "${data.vault_generic_secret.vmware.data["username"]}"
    password = "${data.vault_generic_secret.vmware.data["password"]}"
    vsphere_server = "${data.vault_generic_secret.vmware.data["server"]}"
    allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
    name = "${data.vault_generic_secret.vmware.data["datacenter"]}"
}

data "vsphere_datastore" "datastore" {
    name = "${data.vault_generic_secret.vmware.data["esx_datastore"]}"
    datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_compute_cluster" "cluster" {
    name = "${data.vault_generic_secret.vmware.data["cluster"]}"
    datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_network" "network" {
    name = "VM Network"
    datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_virtual_machine" "template" {
    name = "packer_ubuntu20"
    datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

variable "computer_prefix" {
    type = string
    default = "vuws"
}

variable "instance_count" {
    default = "3"
}

resource "vsphere_virtual_machine" "ws" {
    wait_for_guest_net_timeout = 45
    count = var.instance_count
    name = "${var.computer_prefix}0${count.index + 1}"
    resource_pool_id = "${data.vsphere_compute_cluster.cluster.resource_pool_id}"
    datastore_id = "${data.vsphere_datastore.datastore.id}"

    num_cpus = 4
    memory = 8192
    guest_id = "${data.vsphere_virtual_machine.template.guest_id}"
    scsi_type = "${data.vsphere_virtual_machine.template.scsi_type}"

    enable_logging = true

    network_interface {
      network_id = "${data.vsphere_network.network.id}"
      adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
    }

    disk {
        label = "disk0"
        size = "${data.vsphere_virtual_machine.template.disks.0.size}"
        eagerly_scrub = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
        thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
    }

    clone {
        template_uuid = "${data.vsphere_virtual_machine.template.id}"

        customize {
          timeout = 0
          linux_options {
              host_name = "${var.computer_prefix}0${count.index + 1}"
              domain = "odennav.labs"
          }

          network_interface {
          }
        }
    }

    provisioner "file" {
        source = "../../keys/mykey.pub"
        destination = "/home/ubuntu/mykey.pub"

        connection {
            type = "ssh"
            user = "ubuntu"
            password = "ubuntu"
            host = self.default_ip_address
        }
    }

    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /home/ubuntu/.ssh",
            "sudo chmod 700 /home/ubuntu/.ssh",
            "sudo touch /home/ubuntu/.ssh/authorized_keys",
            "sudo sh -c 'cat /home/ubuntu/mykey.pub > /home/ubuntu/.ssh/authorized_keys'",
            "sudo chown -R ubuntu: /home/ubuntu/.ssh",
            "sudo chmod -R 644 /home/ubuntu/.ssh/authorized_keys",
            "sudo rm -rf /home/ubuntu/mykey.pub"
        ]

        connection {
            type = "ssh"
            user = "ubuntu"
            password = "ubuntu"
            host = self.default_ip_address
        }
    }
}

resource "vsphere_virtual_machine" "lb" {
    wait_for_guest_net_timeout = 45
    name = "lb01"
    resource_pool_id = "${data.vsphere_compute_cluster.cluster.resource_pool_id}"
    datastore_id = "${data.vsphere_datastore.datastore.id}"

    num_cpus = 4
    memory = 8192
    guest_id = "${data.vsphere_virtual_machine.template.guest_id}"
    scsi_type = "${data.vsphere_virtual_machine.template.scsi_type}"

    enable_logging = true

    network_interface {
      network_id = "${data.vsphere_network.network.id}"
      adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
    }

    disk {
        label = "disk0"
        size = "${data.vsphere_virtual_machine.template.disks.0.size}"
        eagerly_scrub = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
        thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
    }

    clone {
        template_uuid = "${data.vsphere_virtual_machine.template.id}"

        customize {
          timeout = 0
          linux_options {
              host_name = "lb01"
              domain = "odennav.labs"
          }

          network_interface {
          }
        }
    }

    provisioner "file" {
        source = "../../keys/mykey.pub"
        destination = "/home/ubuntu/mykey.pub"

        connection {
            type = "ssh"
            user = "ubuntu"
            password = "ubuntu"
            host = self.default_ip_address
        }
    }

    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /home/ubuntu/.ssh",
            "sudo chmod 700 /home/ubuntu/.ssh",
            "sudo touch /home/ubuntu/.ssh/authorized_keys",
            "sudo sh -c 'cat /home/ubuntu/mykey.pub > /home/ubuntu/.ssh/authorized_keys'",
            "sudo chown -R ubuntu: /home/ubuntu/.ssh",
            "sudo chmod -R 644 /home/ubuntu/.ssh/authorized_keys",
            "sudo rm -rf /home/ubuntu/mykey.pub"
        ]

        connection {
            type = "ssh"
            user = "ubuntu"
            password = "ubuntu"
            host = self.default_ip_address
        }
    }
}

resource "local_file" "ansible_inventory" {
    content = templatefile("../artifacts/hosts_myapp.tpl",
    {
        ws_ip = vsphere_virtual_machine.ws.*.default_ip_address
        lb_ip = vsphere_virtual_machine.lb.*.default_ip_address
    })
    filename = "../../ansible/ansible.inventory"
}

output "ws_ips" {
    value = "${formatlist("%v - %v", vsphere_virtual_machine.ws.*.default_ip_address, vsphere_virtual_machine.ws.*.name)}"
}

output "lb_ips" {
    value = "${formatlist("%v - %v", vsphere_virtual_machine.lb.*.default_ip_address, vsphere_virtual_machine.lb.*.name)}"
}