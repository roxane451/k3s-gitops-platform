# DNS Configuration for example.com

locals {
  preprod_dns_target = coalesce(var.preprod_public_ip, var.production_public_ip)
}

# =============================================================================
# PRODUCTION
# =============================================================================
resource "ovh_domain_zone_record" "apex_a" {
  zone      = var.domain_name
  subdomain = ""
  fieldtype = "A"
  ttl       = 3600
  target    = var.production_public_ip
}

resource "ovh_domain_zone_record" "www_a" {
  zone      = var.domain_name
  subdomain = "www"
  fieldtype = "A"
  ttl       = 3600
  target    = var.production_public_ip
}

resource "ovh_domain_zone_record" "api_a" {
  zone      = var.domain_name
  subdomain = "api"
  fieldtype = "A"
  ttl       = 3600
  target    = var.production_public_ip
}

resource "ovh_domain_zone_record" "argocd_a" {
  zone      = var.domain_name
  subdomain = "argocd"
  fieldtype = "A"
  ttl       = 3600
  target    = var.production_public_ip
}

resource "ovh_domain_zone_record" "grafana_a" {
  zone      = var.domain_name
  subdomain = "grafana"
  fieldtype = "A"
  ttl       = 3600
  target    = var.production_public_ip
}

# =============================================================================
# PREPROD
# =============================================================================
resource "ovh_domain_zone_record" "preprod_a" {
  zone      = var.domain_name
  subdomain = "preprod"
  fieldtype = "A"
  ttl       = 3600
  target    = local.preprod_dns_target
}

resource "ovh_domain_zone_record" "www_preprod_a" {
  zone      = var.domain_name
  subdomain = "www.preprod"
  fieldtype = "A"
  ttl       = 3600
  target    = local.preprod_dns_target
}

resource "ovh_domain_zone_record" "api_preprod_a" {
  zone      = var.domain_name
  subdomain = "api.preprod"
  fieldtype = "A"
  ttl       = 3600
  target    = local.preprod_dns_target
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "dns_records" {
  description = "DNS records created"
  value = {
    root        = ovh_domain_zone_record.apex_a.target
    www         = ovh_domain_zone_record.www_a.target
    api         = ovh_domain_zone_record.api_a.target
    preprod     = ovh_domain_zone_record.preprod_a.target
    www_preprod = ovh_domain_zone_record.www_preprod_a.target
    api_preprod = ovh_domain_zone_record.api_preprod_a.target
  }
}
