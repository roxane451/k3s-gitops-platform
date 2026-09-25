terraform {
  required_version = "~> 1.7"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 1.8"
    }
  }
}

# Les credentials OVH sont injectés par `infisical run` sous forme de
# variables d'environnement TF_VAR_ovh_* (voir README).
# Ils ne sont ni dans le code, ni dans un fichier .tfvars, ni dans le state :
# la configuration d'un provider n'est jamais persistée dans le state Terraform.
provider "ovh" {
  endpoint           = var.ovh_endpoint
  application_key    = var.ovh_app_key
  application_secret = var.ovh_app_secret
  consumer_key       = var.ovh_consumer_key
}
