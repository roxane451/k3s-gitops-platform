# Terraform — OVHcloud

Gestion Terraform de la zone DNS `example.com` et du VPS OVH hébergeant le cluster K3s.

## Contenu

| Fichier | Rôle |
|---|---|
| `provider.tf` | Provider `ovh/ovh` (~> 1.8), credentials passés par variables sensibles |
| `backend.tf` | State distant dans HCP Terraform (workspaces `platform-preprod` / `platform-prod`) |
| `main.tf` | VPS existant, importé dans le state (`prevent_destroy`) |
| `dns.tf` | Enregistrements A production et préproduction |
| `ovh_vps_ordering.tf` | Commande de nouveaux VPS pour une évolution multinœud — **désactivé par défaut** (`create_new_vps = false`) |
| `variables.tf` | Variables du module |
| `terraform.tfvars.example` | Exemple de variables non sensibles |

## Gestion des credentials

Les clés API OVH sont stockées dans Infisical sous les noms `TF_VAR_ovh_app_key`,
`TF_VAR_ovh_app_secret` et `TF_VAR_ovh_consumer_key`. `infisical run` les injecte
comme variables d'environnement, que Terraform lit automatiquement.

Conséquences :

- aucun credential dans le code ni dans un fichier `.tfvars` ;
- aucun credential dans le state (la configuration d'un provider n'y est pas persistée,
  contrairement aux valeurs lues par un data source).

Le fichier `.infisical.json` lie ce dossier au projet Infisical ; la CLI l'utilise
automatiquement, il n'est donc pas nécessaire de passer `--projectId`. Dans ce dépôt
public, son `workspaceId` est un placeholder (`infisical init` le régénère).

## Utilisation

Prérequis : Terraform ~> 1.7, CLI Infisical (`infisical login`), accès HCP Terraform (`terraform login`).

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # valeurs non sensibles uniquement

infisical run --env preprod -- terraform init
infisical run --env preprod -- terraform plan  -var-file=terraform.tfvars
infisical run --env preprod -- terraform apply -var-file=terraform.tfvars
```

Vérifications (exécutées aussi par la CI) :

```bash
terraform fmt -check -recursive
terraform init -backend=false && terraform validate
tflint
```

## Provisioning d'un nouveau VPS

`ovh_vps_ordering.tf` prépare l'ajout de nœuds au cluster. Toutes ses ressources
sont conditionnées par `create_new_vps` : un plan standard ne crée ni panier ni
commande. L'activer déclenche une **commande payante** :

```bash
infisical run --env preprod -- terraform plan -var-file=terraform.tfvars -var create_new_vps=true
```

## Snapshots

Le provider `ovh/ovh` ne gère pas les snapshots de VPS. Ils sont déclenchés hors
Terraform, via l'API OVH ou l'espace client, et documentés dans
[`runbooks/rebuild-vps.md`](../runbooks/rebuild-vps.md).
