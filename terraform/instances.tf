
# Creating Nomad Bootstrap token
resource "random_uuid" "consul_default_token" {
}


# Creating the instance template to be use from instances
resource "google_compute_instance_template" "instance_template" {
  # count = var.numnodes
  name_prefix  = "hashistack-servers-"
  machine_type = var.gcp_instance
  region       = var.gcp_region

  tags = [var.cluster_name,var.owner]

  // boot disk
  disk {
    source_image = data.google_compute_image.my_image.self_link
    device_name = "consul-${var.cluster_name}"
    # source = google_compute_region_disk.vault_disk.name
  }
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.self_link

    access_config {
      # nat_ip = google_compute_address.server_addr.address
    }
  }
  service_account {
    email  = data.google_service_account.owner_project.email
    scopes = ["cloud-platform", "compute-rw", "compute-ro", "userinfo-email", "storage-ro"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_template" "instance_template_clients" {
  # count = var.numclients
  name_prefix  = "hashistack-clients-"
  machine_type = var.gcp_instance
  region       = var.gcp_region

  tags = [var.cluster_name,var.owner]

  // boot disk
  disk {
    source_image = data.google_compute_image.my_image.self_link
    device_name = "consul-${var.cluster_name}"
    # source = google_compute_region_disk.vault_disk.name
  }
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.self_link

    access_config {
      # nat_ip = google_compute_address.server_addr.address
    }
  }
  service_account {
    email  = data.google_service_account.owner_project.email
    scopes = ["cloud-platform", "compute-rw", "compute-ro", "userinfo-email", "storage-ro"]
  }
  

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_from_template" "vm_server" {
  count = var.numnodes
  name = "vm-server-${count.index}-${random_id.server.dec}"
  zone = var.gcp_zone

  source_instance_template = google_compute_instance_template.instance_template.id

  // Override fields from instance template
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.self_link
    access_config {
        nat_ip = google_compute_address.server_addr[count.index].address
    }
  }
  metadata_startup_script = templatefile("${path.module}/template/template.tpl",{
    dc_name = var.cluster_name,
    gcp_project = var.gcp_project,
    tag = var.cluster_name,
    consul_license = var.consul_license,
    zone = var.gcp_zone,
    region = var.gcp_region,
    bootstrap_token = var.consul_bootstrap_token,
    default_token = random_uuid.consul_default_token.result,
    node_name = "server-${count.index}",
    nodes = var.numnodes
  })

  labels = {
    node = "server-${count.index}"
  }
  # lifecycle {
  #   create_before_destroy = true
  # }
}

resource "google_compute_instance_from_template" "vm_clients" {
  count = var.numclients
  name = "vm-clients-${count.index}-${random_id.server.dec}"
  zone = var.gcp_zone

  source_instance_template = google_compute_instance_template.instance_template_clients.id

  // Override fields from instance template
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.self_link
    access_config {
        nat_ip = google_compute_address.client_addr[count.index].address
    }
  }

  metadata_startup_script = templatefile("${path.module}/template/template-client.tpl",{
    dc_name = var.cluster_name,
    gcp_project = var.gcp_project,
    tag = var.cluster_name,
    consul_license = var.consul_license,
    bootstrap_token = var.consul_bootstrap_token,
    zone = var.gcp_zone,
    region = var.gcp_region,
    node_name = "client-${count.index}",
    default_token = random_uuid.consul_default_token.result,
    envoy_version = var.envoy_version
  })

  labels = {
    node = "client-${count.index}"
  }
  # lifecycle {
  #   create_before_destroy = true
  # }
}

resource "google_compute_instance_from_template" "vm_cts" {
  count = var.enable_cts ? 1 : 0
  name = "vm-cts-${random_id.server.dec}"
  zone = var.gcp_zone

  source_instance_template = google_compute_instance_template.instance_template_clients.id

  // Override fields from instance template
  network_interface {
    subnetwork = google_compute_subnetwork.subnet.self_link
    access_config {}
  }

  metadata_startup_script = templatefile("${path.module}/template/template-cts.tpl",{
    dc_name = var.cluster_name,
    gcp_project = var.gcp_project,
    tag = var.cluster_name,
    consul_license = var.consul_license,
    bootstrap_token = var.consul_bootstrap_token,
    region = var.gcp_region,
    node_name = "client-cts",
    tfc_token = var.tfc_token,
    default_token = random_uuid.consul_default_token.result,
  })

  labels = {
    node = "client-cts"
  }
  # lifecycle {
  #   create_before_destroy = true
  # }
}



# Create an instance group from the vms
resource "google_compute_instance_group" "hashi_group" {
  depends_on = [
    google_compute_instance_template.instance_template,
    google_compute_instance_template.instance_template_clients
  ]
  name      = "${var.cluster_name}-instance-group"
  zone      = var.gcp_zone
  instances = google_compute_instance_from_template.vm_server.*.self_link
  named_port {
    name = "consul"
    port = 8500
  }
  named_port {
    name = "consul-sec"
    port = 8501
  }
  named_port {
    name = "consul-grpc"
    port = 8502
  }
  named_port {
    name = "consul-lan"
    port = 8301
  }
  named_port {
    name = "consul-wan"
    port = 8302
  }
  named_port {
    name = "consul-server"
    port = 8300
  }

  # lifecycle {
  #   create_before_destroy = true
  # }
}

resource "google_compute_instance_group" "app_group" {
  depends_on = [
    google_compute_instance_template.instance_template,
    google_compute_instance_template.instance_template_clients
  ]
  name      = "${var.cluster_name}-instance-group-client"
  zone      = var.gcp_zone
  instances = google_compute_instance_from_template.vm_clients.*.self_link
  named_port {
    name = "frontend"
    port = 80
  }
  # lifecycle {
  #   create_before_destroy = true
  # }
}