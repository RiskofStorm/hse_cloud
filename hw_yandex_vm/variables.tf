variable "cloud_id" {
  type = string
}

variable "folder_id" {
  type = string
}

variable "zone" {
  type    = string
  default = "ru-central1-a"
}

variable "vm_name" {
  type    = string
  default = "demo-vm"
}

variable "ssh_user" {
  type    = string
  default = "winter"
}

variable "ssh_public_key" {
  type = string
}

variable "yc_image_id" {
  type    = string
  default = "fd8m51h9aeq2r6s7q2u4"
}
