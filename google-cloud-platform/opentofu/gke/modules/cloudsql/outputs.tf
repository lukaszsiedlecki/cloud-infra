output "instance_name" {
  value = google_sql_database_instance.main.name
}

output "private_ip_address" {
  value = google_sql_database_instance.main.private_ip_address
}

output "shortliner_db_user" {
  value = google_sql_user.shortliner.name
}

output "shortliner_db_password" {
  value     = random_password.shortliner_db.result
  sensitive = true
}

output "shortliner_analytics_db_user" {
  value = google_sql_user.shortliner_analytics.name
}

output "shortliner_analytics_db_password" {
  value     = random_password.shortliner_analytics_db.result
  sensitive = true
}
