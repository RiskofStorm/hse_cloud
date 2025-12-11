terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      # version можешь добавить, например:
      # version = "~> 0.122"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone = "ru-central1-a"
}
