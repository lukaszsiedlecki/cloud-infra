output "app_record_fqdn" {
  value = cloudflare_dns_record.app.name
}

output "cert_validation_record_fqdn" {
  value = cloudflare_dns_record.cert_validation.name
}
