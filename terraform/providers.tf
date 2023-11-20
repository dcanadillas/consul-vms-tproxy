terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "5.6.0"
    }
  }
}


provider "google" {
  project = var.gcp_project
  region = var.gcp_region
}