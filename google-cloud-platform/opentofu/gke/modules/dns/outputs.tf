output "app_record_fqdn" {
  value = cloudflare_dns_record.app.name
}
