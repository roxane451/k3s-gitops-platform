# terraform/backend.tf
# State Terraform stocké dans Terraform Cloud (HCP Terraform free tier)
#
# Prérequis :
#   1. Créer un compte sur https://app.terraform.io
#   2. Créer une organisation et reporter son nom ci-dessous
#   3. Créer 2 workspaces : "platform-preprod" et "platform-prod"
#      → Execution Mode : Local  (le plan s'exécute sur votre poste)
#      → Onglet "Variables" : ajouter les TF_VAR_ovh_* en Sensitive
#   4. Générer un token : User Settings → Tokens → Create
#   5. terraform login  (une seule fois — stocké dans ~/.terraform.d/credentials.tfrc.json)
#   6. terraform init
#
# Le workspace actif est sélectionné via TF_WORKSPACE ou -workspace= en CLI.
# Par défaut : platform-preprod

terraform {
  cloud {
    organization = "<HCP_TERRAFORM_ORG>"

    workspaces {
      name = "platform-preprod"
    }
  }
}
