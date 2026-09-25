# ── OVH API ───────────────────────────────────────────────
# Fournies par Infisical via `infisical run` (TF_VAR_ovh_*).
variable "ovh_endpoint" {
  description = "OVH API endpoint"
  type        = string
  default     = "ovh-eu"
}

variable "ovh_app_key" {
  description = "OVH API application key"
  type        = string
  sensitive   = true
}

variable "ovh_app_secret" {
  description = "OVH API application secret"
  type        = string
  sensitive   = true
}

variable "ovh_consumer_key" {
  description = "OVH API consumer key"
  type        = string
  sensitive   = true
}

# ── Domaine / DNS ─────────────────────────────────────────
variable "domain_name" {
  description = "DNS zone managed by Terraform"
  type        = string
  default     = "example.com"
}

variable "production_public_ip" {
  description = "Public IPv4 used for production DNS records"
  type        = string
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.production_public_ip))
    error_message = "production_public_ip must be a valid IPv4 address."
  }
}

variable "preprod_public_ip" {
  description = "Optional public IPv4 for preprod (defaults to production_public_ip)"
  type        = string
  default     = null
  nullable    = true
}

# ── Provisioning de nouveaux VPS (désactivé par défaut) ───
# Voir ovh_vps_ordering.tf. Passer create_new_vps = true déclenche
# une COMMANDE PAYANTE chez OVH.
variable "create_new_vps" {
  description = "Order a new OVH VPS (billable). Keep false unless extending the cluster."
  type        = bool
  default     = false
}

variable "vps_display_name" {
  description = "Display name of the new VPS"
  type        = string
  default     = "app-node-2"
}

variable "vps_plan_code" {
  description = "OVH VPS plan code (e.g. vps-2025-model1)"
  type        = string
  default     = "vps-2025-model1"
}

variable "vps_datacenter" {
  description = "OVH datacenter for the new VPS"
  type        = string
  default     = "GRA"
}

variable "vps_os" {
  description = "OS image for the new VPS"
  type        = string
  default     = "Debian 12"
}
