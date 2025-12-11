resource "yandex_vpc_network" "this" {
  name = "demo-network"
}

resource "yandex_vpc_subnet" "this" {
  name           = "demo-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = ["10.0.0.0/24"]
}

resource "yandex_compute_instance" "vm" {
  name        = var.vm_name
  platform_id = "standard-v3"
  zone        = var.zone

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = var.yc_image_id
      size     = 20
      type     = "network-ssd"
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.this.id
    nat       = true
  }

  metadata = {
    user-data = <<-EOF
      #cloud-config
      users:
        - name: ${var.ssh_user}
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh-authorized-keys:
            - ${var.ssh_public_key}
    EOF
  }
}

output "vm_external_ip" {
  value = yandex_compute_instance.vm.network_interface[0].nat_ip_address
}
