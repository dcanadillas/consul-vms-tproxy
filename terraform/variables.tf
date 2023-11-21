variable "gcp_region" {
  description = "Google Cloud region"
}
variable "gcp_zone" {
  description = "Google Cloud region"
  validation {
    # Validating that zone is within the region
    condition     = var.gcp_zone == regex("[a-z]+-[a-z]+[0-1]-[abc]",var.gcp_zone)
    error_message = "The GCP zone ${var.gcp_zone} needs to be a valid one."
  }

}
variable "gcp_project" {
  description = "Cloud project"
}
variable "gcp_sa" {
  description = "GCP Service Account to use for scopes"
}
variable "gcp_instance" {
  description = "Machine type for nodes"
}
# variable "gcp_zones" {
#   description = "availability zones"
#   type = list(string)
# }
variable "numnodes" {
  description = "number of server nodes"
  default = 3
}
variable "numclients" {
  description = "number of client nodes"
  default = 2
}
variable "enable_cts" {
  description = "True if a CTS VM is deployed. Default is \"true\""
  default = true
}
variable "cluster_name" {
  description = "Name of the cluster"
}
variable "owner" {
  description = "Owner of the cluster"
}
variable "server" {
  description = "Prefix for server names"
  default = "consul-server"
}
variable "consul_license" {
  description = "Consul Enterprise license text"
}

variable "tfc_token" {
  description = "Terraform Cloud token to use for CTS"
  default = ""
}

variable "consul_bootstrap_token" {
  description = "Terraform Cloud token to use for CTS"
  default = "ConsulR0cks!"
}

variable "image_family" {
  default = "dcanadillas-consul"
}

variable "dns_zone" {
  default = "doormat-useremail"
}

variable "envoy_version" {
  default = "1.26.6"
}