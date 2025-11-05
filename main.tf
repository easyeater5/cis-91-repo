terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.8.0"
    }
  }
}

provider "google" {
    project = var.project
    region  = var.region
    zone    = var.zone
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_instance" "vm_instance" {
  name         = "terraform-instance"
  machine_type = "e2-small"
  tags         = ["web", "dev"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      #image = "debian-cloud/debian-12"
      image = "cos-cloud/cos-stable"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
    }
  }
}

output "ip" {
  value = google_compute_instance.vm_instance.network_interface.0.network_ip
}

output "exturnal_ip" {
  value = google_compute_instance.vm_instance.network_interface.0.access_config.0.nat_ip
}