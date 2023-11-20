output "consul_load_balancer" {
  value = google_compute_forwarding_rule.global-lb.ip_address
}
output "hashicups_load_balancer" {
  value = google_compute_forwarding_rule.clients-lb.ip_address
}
output "CONSULT_HTTP_ADDR" {
  value = "https://${trimsuffix(google_dns_record_set.dns.name,".")}:8501"
}
output "CONSUL_TOKEN" {
  value = var.consul_bootstrap_token
  sensitive = true
}
# output "server_hosts" {
#   value = { for i,j in google_compute_instance_from_template.vm_server : "gcp-instance-${i}" => j.name }
# }
# output "clients_hosts" {
#   value = { for i,j in google_compute_instance_from_template.vm_clients : "gcp-instance-${i}" => j.name }
# }
output "gcp_servers" {
  value = [ for i in google_compute_instance_from_template.vm_server : "gcloud compute ssh ${i.name} --zone ${i.zone}"]
}
output "gcp_clients" {
  value = [ for i in google_compute_instance_from_template.vm_clients : "gcloud compute ssh ${i.name} --zone ${i.zone}"]
}