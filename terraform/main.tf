# VPS existant, intégré au state via `terraform import`.
#
# Aucun attribut n'est "required" dans le schéma du provider ovh/ovh pour
# ovh_vps (tous sont optional+computed ou computed) : les valeurs sont lues
# depuis l'API OVH après l'import plutôt que devinées.

resource "ovh_vps" "preprod" {
  lifecycle {
    prevent_destroy = true

    # Bug connu du provider ovh/ovh : l'attribut plan revient sous forme de
    # liste vide au lieu de null après apply, ce qui casse la vérification
    # de cohérence de Terraform.
    ignore_changes = [plan]
  }
}
