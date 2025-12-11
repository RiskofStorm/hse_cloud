terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.122"
    }
  }

  required_version = ">= 1.5.0"
}

provider "yandex" {
  service_account_key_file = "${path.module}/key.json"
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  zone                     = var.zone
}
