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

resource "google_service_account" "vm_service_account" {
  account_id   = "vm-service-account"
  display_name = "Service Account for VM Instance"
}

resource "google_compute_network" "vpc_network" {
  name = "terraform-network"
}

resource "google_compute_disk" "data_disk" {
  name           = "data-disk"
  type           = "pd-balanced"
  zone           = var.zone
  size           = 50
  physical_block_size_bytes = 4096
}

resource "google_compute_instance" "db_instance" {
  name         = "db-instance"
  machine_type = "e2-small"
  tags         = ["db"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
    }
  }

  service_account {
    email  = google_service_account.vm_service_account.email
    scopes = ["cloud-platform"]
  }

  attached_disk {
    source      = google_compute_disk.data_disk.self_link
    device_name = "data-disk"
  }
}



resource "google_compute_instance" "web_instance" {
  name         = "web-instance"
  machine_type = "e2-small"
  tags         = ["web"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {
    }
  }

}

output "db-ip" {
  value = google_compute_instance.db_instance.network_interface.0.network_ip
}

output "web-ip" {
  value = google_compute_instance.web_instance.network_interface.0.network_ip
}

output "external_ip" {
  value = google_compute_instance.web_instance.network_interface.0.access_config.0.nat_ip
}

resource "google_compute_firewall" "allow-http-ssh-https" {
  name    = "allow-http-ssh-https"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web"]
}

resource "google_compute_firewall" "allow-db-ssh" {
  name    = "allow-db-ssh"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["db"]
}

resource "google_compute_firewall" "allow-db" {
  name    = "allow-db"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }

  source_tags   = ["web"]
  target_tags   = ["db"]
}