terraform {
  required_version = ">= 1.0.0"
  # backend "remote" {
  # }
}

resource "random_id" "server" {
  byte_length = 1
}

# Collect client config for GCP
data "google_client_config" "current" {
}
data "google_service_account" "owner_project" {
  account_id = var.gcp_sa
}



## ----- Network capabilities ------
# VPC creation
resource "google_compute_network" "network" {
  name = "${var.cluster_name}-network"
}


# Subnet creation
resource "google_compute_subnetwork" "subnet" {
  name = "${var.cluster_name}-subnetwork"

  ip_cidr_range = "10.2.0.0/16"
  region        = var.gcp_region
  network       = google_compute_network.network.id
}

# Create an ip address for the load balancer
resource "google_compute_address" "global-ip" {
  name = "lb-ip"
  region = var.gcp_region
}

# External IP addresses
resource "google_compute_address" "server_addr" {
  count = var.numnodes
  name  = "server-addr-${count.index}"
  # subnetwork = google_compute_subnetwork.subnet.id
  region = var.gcp_region
}

resource "google_compute_address" "client_addr" {
  count = var.numclients
  name  = "client-addr-${count.index}"
  # subnetwork = google_compute_subnetwork.subnet.id
  region = var.gcp_region
}

# Create firewall rules

resource "google_compute_firewall" "default" {
  name    = "hashi-rules"
  network = google_compute_network.network.name

  allow {
    protocol = "tcp"
    ports    = ["80","443","8500","8501","8502","8503","22","8300","8301","8400","8302","8600","8443"]
  }
  allow {
    protocol = "udp"
    ports = ["8600","8301","8302"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = [var.cluster_name,"nomad-${var.cluster_name}","consul-${var.cluster_name}"]
}
# These are internal rules for communication between the nodes internally
resource "google_compute_firewall" "internal" {
  name    = "hashi-internal-rules"
  network = google_compute_network.network.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }

  source_tags = [var.cluster_name,"consul-${var.cluster_name}"]
  target_tags   = [var.cluster_name,"consul-${var.cluster_name}"]
}     

# Creating Load Balancing with different required resources
resource "google_compute_region_backend_service" "default" {
  name          = "${var.cluster_name}-backend-service"
  health_checks = [
    google_compute_region_health_check.default.id
  ]
  region = var.gcp_region
  protocol = "TCP"
  load_balancing_scheme = "EXTERNAL"
  backend {
    group  = google_compute_instance_group.hashi_group.id
    # balancing_mode = "CONNECTION"
  }
}

resource "google_compute_region_backend_service" "hashicups" {
  name          = "${var.cluster_name}-hashicups"
  health_checks = [
    google_compute_region_health_check.default.id
  ]
  region = var.gcp_region
  protocol = "TCP"
  load_balancing_scheme = "EXTERNAL"
  backend {
    group  = google_compute_instance_group.hashi_group.id
    # balancing_mode = "CONNECTION"
  }
}


resource "google_compute_region_health_check" "default" {
  name = "health-check"
  # request_path       = "/"
  check_interval_sec = 1
  timeout_sec        = 1
  region = var.gcp_region

  http_health_check {
    port = "8500"
    request_path = "/ui"
  }
}

resource "google_compute_region_health_check" "hashicups" {
  name = "health-check-hashicups"
  check_interval_sec = 1
  timeout_sec        = 1
  region = var.gcp_region

  http_health_check {
    port = "80"
    request_path = "/"
  }
}

resource "google_compute_forwarding_rule" "global-lb" {
  name       = "hashistack-lb"
  # ip_address = google_compute_global_address.global-ip.address
  ip_address = google_compute_address.global-ip.address
  # target     = google_compute_target_pool.vm-pool.self_link
  backend_service = google_compute_region_backend_service.default.id
  region = var.gcp_region
  ip_protocol = "TCP"
  ports = ["4646-4648","8500-8503","8600","9701-9702","8443"]
}

resource "google_compute_forwarding_rule" "clients-lb" {
  name       = "clients-lb"
  #  ip_address = google_compute_address.global-ip.address
  backend_service = google_compute_region_backend_service.hashicups.id
  region = var.gcp_region
  ip_protocol = "TCP"
  ports = ["80","443","8443","8080"]
}





data "google_compute_image" "my_image" {
  family  = var.image_family
  project = var.gcp_project
}

# data "google_dns_managed_zone" "doormat_dns_zone" {
#   name = var.dns_zone
# }

# resource "google_dns_record_set" "dns" {
#   name = "hashi.${data.google_dns_managed_zone.doormat_dns_zone.dns_name}"
#   type = "A"
#   ttl  = 300

#   managed_zone = data.google_dns_managed_zone.doormat_dns_zone.name

#   rrdatas = [google_compute_forwarding_rule.global-lb.ip_address]
# }
