provider_installation {
  network_mirror {
    url = "https://terraform.yandexcloud.net/"

    include = ["yandex-cloud/*"]
  }

  direct {
    exclude = ["yandex-cloud/*"]
  }
}
