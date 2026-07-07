provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Reads the token from the CLOUDFLARE_API_TOKEN env var — never set it here.
provider "cloudflare" {}

data "google_project" "current" {
  project_id = var.project_id
}

module "network" {
  source = "./modules/network"

  name_prefix = var.name_prefix
  region      = var.region
}

module "gke_autopilot" {
  source = "./modules/gke-autopilot"

  name_prefix       = var.name_prefix
  project_id        = var.project_id
  region            = var.region
  network_self_link = module.network.network_self_link
  subnet_self_link  = module.network.subnet_self_link
}

module "cloudsql" {
  source = "./modules/cloudsql"

  name_prefix                       = var.name_prefix
  project_id                        = var.project_id
  region                            = var.region
  tier                              = var.db_tier
  network_id                        = module.network.network_id
  private_service_access_connection = module.network.private_service_access_connection
}

module "iam" {
  source = "./modules/iam"

  name_prefix = var.name_prefix
  project_id  = var.project_id
}

module "secrets" {
  source = "./modules/secrets"

  project_id             = var.project_id
  project_number         = data.google_project.current.number
  workload_identity_pool = module.gke_autopilot.workload_identity_pool

  shortliner_db_user               = module.cloudsql.shortliner_db_user
  shortliner_db_password           = module.cloudsql.shortliner_db_password
  shortliner_analytics_db_user     = module.cloudsql.shortliner_analytics_db_user
  shortliner_analytics_db_password = module.cloudsql.shortliner_analytics_db_password
}

module "gateway" {
  source = "./modules/gateway"

  name_prefix = var.name_prefix
  project_id  = var.project_id
  domain      = var.domain
}

module "dns" {
  source = "./modules/dns"

  zone_name         = var.cloudflare_zone
  app_hostname      = var.domain
  static_ip_address = module.gateway.static_ip_address

  dns_authorization_record_name = module.gateway.dns_authorization_dns_resource_record[0].name
  dns_authorization_record_data = module.gateway.dns_authorization_dns_resource_record[0].data
}
