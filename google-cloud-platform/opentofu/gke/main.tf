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

# Looked up once here (not inside the dns/tunnel modules) since both need
# it and each depends on an output of the other (dns needs the tunnel_id,
# tunnel needs the account_id) — doing the lookup in either module would
# create a circular module dependency.
data "cloudflare_zone" "main" {
  filter = {
    name = var.cloudflare_zone
  }
}

module "network" {
  source = "./modules/network"

  name_prefix = var.name_prefix
  region      = var.region
}

module "gke" {
  source = "./modules/gke"

  name_prefix       = var.name_prefix
  project_id        = var.project_id
  zone              = var.zone
  network_self_link = module.network.network_self_link
  subnet_self_link  = module.network.subnet_self_link

  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
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

  name_prefix    = var.name_prefix
  project_id     = var.project_id
  project_number = data.google_project.current.number
}

module "tunnel" {
  source = "./modules/tunnel"

  account_id     = data.cloudflare_zone.main.account.id
  tunnel_name    = var.name_prefix
  app_hostname   = var.domain
  origin_service = "shortliner-frontend-svc:80"
}

module "dns" {
  source = "./modules/dns"

  zone_id      = data.cloudflare_zone.main.id
  app_hostname = var.domain
  tunnel_id    = module.tunnel.tunnel_id
}

module "secrets" {
  source = "./modules/secrets"

  project_id             = var.project_id
  project_number         = data.google_project.current.number
  workload_identity_pool = module.gke.workload_identity_pool

  db_host                           = module.cloudsql.private_ip_address
  shortliner_db_user               = module.cloudsql.shortliner_db_user
  shortliner_db_password           = module.cloudsql.shortliner_db_password
  shortliner_analytics_db_user     = module.cloudsql.shortliner_analytics_db_user
  shortliner_analytics_db_password = module.cloudsql.shortliner_analytics_db_password
  tunnel_token                     = module.tunnel.tunnel_token
}
