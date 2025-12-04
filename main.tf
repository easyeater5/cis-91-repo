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

resource "google_project_iam_member" "monitoring_writer" {
  project = var.project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.vm_service_account.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.vm_service_account.email}"
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
    source = google_compute_disk.data_disk.id
    device_name = "data-disk"
  }
}



resource "google_compute_instance" "web_instance" {
  count        = var.scale
  name         = "web-instance-${count.index}"
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

  service_account {
    email  = google_service_account.vm_service_account.email
    scopes = ["cloud-platform"]
  }

}

output "db-ip" {
  value = google_compute_instance.db_instance.network_interface[0].network_ip
}

output "web-ip" {
  value = [for instance in google_compute_instance.web_instance : instance.network_interface[0].network_ip]
}

output "external_ip" {
  value = [for instance in google_compute_instance.web_instance : instance.network_interface[0].access_config[0].nat_ip]
}

output "lb_ip_address" {
  description = "The IP address of the load balancer."
  value       = google_compute_global_forwarding_rule.http_lb.ip_address
}

resource "google_compute_health_check" "http_health_check" {
  name                = "http-basic-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port = 80
  }
}

resource "google_compute_instance_group" "web_instance_group" {
  name      = "web-instance-group"
  zone      = var.zone
  instances = google_compute_instance.web_instance.*.self_link
}

resource "google_compute_backend_service" "web_backend_service" {
  name        = "web-backend-service"
  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30

  backend {
    group = google_compute_instance_group.web_instance_group.id
  }

  health_checks = [google_compute_health_check.http_health_check.id]
}

resource "google_compute_url_map" "http_lb" {
  name            = "http-lb-url-map"
  default_service = google_compute_backend_service.web_backend_service.id
}

resource "google_compute_target_http_proxy" "http_lb" {
  name    = "http-lb-proxy"
  url_map = google_compute_url_map.http_lb.id
}

resource "google_compute_global_forwarding_rule" "http_lb" {
  name       = "http-lb-forwarding-rule"
  target     = google_compute_target_http_proxy.http_lb.id
  port_range = "80"
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