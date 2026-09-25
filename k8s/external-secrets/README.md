# External Secrets (cluster-wide)

Ce dossier contient les manifests cluster-wide liés à External Secrets Operator.

## Fichiers

- `cluster-secret-store.yaml` : définition des `ClusterSecretStore` Infisical
  - `infisical-store-backend` → production, dossier Infisical `/backend`
  - `infisical-store-r2` → production, dossier Infisical `/r2`
  - `infisical-store-preprod-backend` → preprod, dossier Infisical `/backend`
  - `infisical-store-preprod-mongodb` → preprod, dossier Infisical `/mongodb`
  - `infisical-store-preprod-r2` → preprod, dossier Infisical `/r2`

## ⚠️ Instance Infisical

Ce projet utilise l'instance **européenne** : `https://eu.infisical.com`
(pas `app.infisical.com` qui est l'instance US)

## Prérequis

External Secrets Operator installé sur le cluster :

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

## Authentification

L'authentification vers Infisical utilise **Universal Auth** (Machine Identity) — méthode recommandée depuis 2024, remplace les Service Tokens (legacy).

Deux Machine Identities dédiées sont configurées dans Infisical :

| Machine Identity   | Namespace K8s   | Environnement Infisical |
|--------------------|-----------------|-------------------------|
| `app-eso-prod`    | `app`          | `production`            |
| `app-eso-preprod` | `app-preprod`  | `preprod`               |

## Déploiement

Le bootstrap est géré par Ansible — **ne pas appliquer manuellement**.

```bash
cd ansible

ansible-playbook playbook-k3s.yml \
  -i inventories/production.yml \
  --tags infisical \
  -e infisical_client_id_prod="$INFISICAL_CLIENT_ID_PROD" \
  -e infisical_client_secret_prod="$INFISICAL_CLIENT_SECRET_PROD" \
  -e infisical_client_id_preprod="$INFISICAL_CLIENT_ID_PREPROD" \
  -e infisical_client_secret_preprod="$INFISICAL_CLIENT_SECRET_PREPROD"
```

Le playbook effectue dans l'ordre :
1. Crée les namespaces `app` et `app-preprod`
2. Crée le secret `infisical-token` dans chaque namespace avec les bons credentials
3. Applique le `ClusterSecretStore`
4. Vérifie que le store est `Ready: True`

### Vérification

```bash
kubectl get clustersecretstore
# NAME                            AGE   STATUS   CAPABILITIES   READY
# infisical-store-backend         Xs    Valid    ReadOnly       True
# infisical-store-r2              Xs    Valid    ReadOnly       True
# infisical-store-preprod-backend Xs    Valid    ReadOnly       True
# infisical-store-preprod-mongodb Xs    Valid    ReadOnly       True
# infisical-store-preprod-r2      Xs    Valid    ReadOnly       True
```

## Architecture secrets

```
Infisical (source de vérité)
├── env: production  →  ClusterSecretStore: infisical-store-backend, infisical-store-r2
└── env: preprod     →  ClusterSecretStore: infisical-store-preprod-backend, infisical-store-preprod-mongodb, infisical-store-preprod-r2
        ↓
ExternalSecrets Operator lit Infisical et crée les Secrets K8s
        ↓
chart Helm monte les secrets dans les pods via secretRef
```

Les ExternalSecrets sont définis dans le chart applicatif
`app-helm` (chart Helm applicatif, dépôt privé).
