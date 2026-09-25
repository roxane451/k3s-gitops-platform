# ------------------------------------------------------------------
# Provisioning de nouveaux VPS OVHcloud (extension multinœud du cluster).
#
# DÉSACTIVÉ PAR DÉFAUT : toutes les ressources dépendent de
# var.create_new_vps (false). Un plan standard ne crée donc ni panier
# ni commande chez OVH.
#
# Le VPS actuellement en service est géré séparément (main.tf,
# ressource ovh_vps.preprod importée dans le state).
#
# Activation (commande payante) :
#   infisical run --env preprod -- terraform plan -var create_new_vps=true
# ------------------------------------------------------------------

data "ovh_order_cart" "vps_cart" {
  count = var.create_new_vps ? 1 : 0

  ovh_subsidiary = "FR"
  description    = "cart to order a new VPS"
}

data "ovh_order_cart_product_plan" "vps_plan" {
  count = var.create_new_vps ? 1 : 0

  cart_id        = data.ovh_order_cart.vps_cart[0].id
  price_capacity = "renew"
  product        = "vps"
  plan_code      = var.vps_plan_code
}

resource "ovh_vps" "new" {
  count = var.create_new_vps ? 1 : 0

  display_name   = var.vps_display_name
  ovh_subsidiary = data.ovh_order_cart.vps_cart[0].ovh_subsidiary

  plan = [{
    duration     = data.ovh_order_cart_product_plan.vps_plan[0].selected_price[0].duration
    plan_code    = data.ovh_order_cart_product_plan.vps_plan[0].plan_code
    pricing_mode = data.ovh_order_cart_product_plan.vps_plan[0].selected_price[0].pricing_mode

    configuration = [
      {
        label = "vps_datacenter"
        value = var.vps_datacenter
      },
      {
        label = "vps_os"
        value = var.vps_os
      }
    ]
  }]

  # Le provider ovh/ovh 1.8 n'expose pas d'attribut de clé SSH sur ovh_vps :
  # la clé est déposée après livraison (identifiants envoyés par OVH), puis
  # le playbook Ansible de hardening désactive l'authentification par mot de passe.

  # Protection contre une destruction accidentelle, en cohérence
  # avec la stratégie appliquée au VPS existant.
  lifecycle {
    prevent_destroy = true
  }
}

output "new_vps_service_name" {
  description = "OVH service_name of the newly ordered VPS (null when create_new_vps = false)"
  value       = one(ovh_vps.new[*].id)
}
