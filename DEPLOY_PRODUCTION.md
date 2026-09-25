# Déploiement Production OVH

> Ce document couvre le **premier déploiement from scratch** en production.
> Pour les mises à jour applicatives, ArgoCD suit la branche `main` de
> `app-helm` (chart Helm applicatif, dépôt privé) ; en production,
> la synchronisation reste **manuelle** (voir §10).

---

## Différences clés vs Preprod

| Point | Preprod | Production |
|---|---|---|
| Infisical env | `preprod` | `prod` |
| Namespace Helm | `app-preprod` | `app` |
| Values Helm | `values-preprod.yaml` | `values-production.yaml` |
| Sync ArgoCD | automatique (`prune` + `selfHeal`) | **manuel** (`make sync-prod`) |
| TLS | Let's Encrypt staging | Let's Encrypt production |
| Replicas | 1 | 2 + HPA 2→4 |
| Seed Job | ✅ activé | ❌ désactivé (données réelles) |
| Backup MongoDB | 7 jours | 30 jours + R2 |
| Snapshot VPS | optionnel | ✅ **avant chaque déploiement** |

---

## 0) Variables d'environnement

Les valeurs propres à l'infrastructure ne sont pas versionnées :

```bash
export OVH_VPS_IP=<IP_DU_VPS>            # lue par ansible/inventories/production.yml
export ADMIN_CIDR=<IP_ADMIN>/32          # SSH, API K3s et UI ArgoCD
export LETSENCRYPT_EMAIL=<EMAIL_ACME>    # compte ACME Let's Encrypt
export KUBECONFIG=~/.kube/config-ovh_vps
```

---

## 1) Snapshot VPS avant tout

> Toujours créer un snapshot OVH avant un déploiement en production : c'est le
> point de restauration en cas d'incident (voir `runbooks/rebuild-vps.md`).

Le provider Terraform `ovh/ovh` ne gère pas les snapshots de VPS : les créer
depuis l'espace client OVH (VPS → Snapshot) ou via l'API OVH
(`POST /vps/{serviceName}/createSnapshot`).

---

## 2) Terraform OVH (DNS)

```bash
cd terraform/
infisical run --env prod -- terraform init
terraform fmt -check
terraform validate
infisical run --env prod -- terraform plan -out=tfplan -var-file=terraform.tfvars
infisical run --env prod -- terraform apply tfplan
```

---

## 3) Ansible — Dépendances Galaxy

```bash
cd ansible/
ansible-playbook playbook-bootstrap.yml --tags bootstrap
```

---

## 4) Ansible — Hardening OS (premier run — port 22)

```bash
ansible-playbook -i inventories/production.yml playbook-k3s.yml \
  --tags hardening \
  -e admin_cidr="$ADMIN_CIDR" \
  -e ansible_port=22 \
  --private-key ~/.ssh/id_ed25519_platform
```

> Après cette étape : SSH bascule sur le port 2222, UFW actif.

---

## 5) Ansible — Installation K3s

```bash
ansible-playbook -i inventories/production.yml playbook-k3s.yml \
  --tags k3s \
  -e k3s_confirm=yes \
  --private-key ~/.ssh/id_ed25519_platform
```

---

## 6) Ansible — External Secrets Operator (ESO)

> Doit s'exécuter **après K3s** et **avant le bootstrap Infisical**.

```bash
ansible-playbook -i inventories/production.yml playbook-k3s.yml \
  --tags eso \
  --private-key ~/.ssh/id_ed25519_platform
```

---

## 7) Ansible — Bootstrap Infisical (ClusterSecretStore)

Les credentials des Machine Identities ne sont jamais écrits dans le dépôt. Les
passer via Ansible Vault ou, ponctuellement, en variables de session :

```bash
ansible-playbook -i inventories/production.yml playbook-k3s.yml \
  --tags infisical \
  -e infisical_client_id_prod="$INFISICAL_CLIENT_ID_PROD" \
  -e infisical_client_secret_prod="$INFISICAL_CLIENT_SECRET_PROD" \
  -e infisical_client_id_preprod="$INFISICAL_CLIENT_ID_PREPROD" \
  -e infisical_client_secret_preprod="$INFISICAL_CLIENT_SECRET_PREPROD"
```

Vérification :

```bash
kubectl get clustersecretstore
# Toutes les stores doivent être READY: True
```

---

## 8) Traefik TLS — Let's Encrypt production

> Le certResolver Traefik utilise l'ACME **production** par défaut. La ligne
> `caserver` staging de `k8s/traefik/traefik-tls.yaml` doit rester commentée.

L'email ACME est injecté à l'application (`envsubst`) pour ne pas être versionné :

```bash
envsubst '${LETSENCRYPT_EMAIL}' < k8s/traefik/traefik-tls.yaml | kubectl apply -f -
kubectl get helmchartconfig traefik -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
```

---

## 9) Stack Monitoring (ArgoCD)

> La stack monitoring doit être déployée **avant le chart applicatif** pour que les CRDs
> (`ServiceMonitor`, `PrometheusRule`) soient disponibles.

```bash
# 1. Prometheus + Grafana (installe les CRDs)
kubectl apply -f k8s/monitoring/application-prometheus.yaml

# 2. Attendre que les CRDs soient prêtes (~2 min)
kubectl get crd | grep monitoring.coreos.com   # doit lister ~12 CRDs
kubectl get pods -n monitoring -w              # attendre Running

# 3. Loki + Promtail
kubectl apply -f k8s/monitoring/application-loki.yaml
```

---

## 10) ArgoCD — Déploiement applicatif production

> En production, le déploiement est géré par ArgoCD avec une synchronisation manuelle.
> Le premier déploiement nécessite d'installer le contrôleur ArgoCD lui-même,
> puis d'appliquer l'Application ArgoCD manuellement.

```bash
# Contrôleur ArgoCD (absent avant cette étape sur un cluster neuf — cf.
# k8s/argocd/namespace.yaml et ingress.yaml, qui supposent ArgoCD déjà présent)
kubectl apply -f k8s/argocd/namespace.yaml
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd -n argocd

# UI ArgoCD restreinte à ADMIN_CIDR (injecté à l'application)
envsubst '${ADMIN_CIDR}' < k8s/argocd/ingress.yaml | kubectl apply -f -

# Application production (values-k3s-base.yaml + values-production.yaml)
kubectl apply -f k8s/argocd/application-production.yaml

# Suivre le sync
kubectl get application app-production -n argocd
kubectl get pods -n app -w
```

> ArgoCD détecte les changements Git (webhook/polling), mais le **sync applicatif
> n'est pas auto-appliqué en production** :
> `application-production.yaml` a son bloc `automated` commenté (contrairement
> à `application-preprod.yaml`, où `selfHeal: true` est actif). Après un push
> sur `main`, synchroniser manuellement : `make sync-prod` (ou
> bouton Sync dans l'UI).

---

## 11) Tests post-déploiement

```bash
# Pods
kubectl get pods -n app

# Ingress
kubectl get ingress -n app

# Certificats TLS — pas de cert-manager dans ce projet, donc pas de ressource
# `Certificate` à interroger. Le certResolver Traefik (TLS-ALPN-01) émet et
# stocke le certificat dans /data/acme.json (PVC du pod Traefik) ; la seule
# vérification fiable est une requête HTTPS réelle :
curl -vI https://example.com 2>&1 | grep -i "subject\|issuer\|SSL certificate"
curl -vI https://api.example.com 2>&1 | grep -i "subject\|issuer\|SSL certificate"

# HPA
kubectl get hpa -n app

# ExternalSecrets
kubectl get externalsecret -n app
# STATUS doit être SecretSynced
```

Vérifications fonctionnelles :

- [ ] API disponible sur `https://api.example.com`
- [ ] UI disponible sur `https://example.com`
- [ ] Certificat TLS valide (Let's Encrypt prod — pas staging)
- [ ] Redirect HTTP → HTTPS actif
- [ ] Grafana accessible sur `https://grafana.example.com`
- [ ] Backup MongoDB actif (`kubectl get cronjob -n app`)

---

## 12) Points d'attention production

- **Ne jamais activer `cert-manager` en parallèle du certResolver Traefik** : conflit silencieux, aucun certificat émis.
- **`seedJob.enabled` doit être `false`** dans `values-production.yaml` — ne pas écraser les données réelles.
- **Rotation des clés OVH** planifiée tous les 6 mois (Infisical).
- **Snapshot VPS** avant chaque mise à jour infrastructure (Ansible/Terraform).
- Les credentials Infisical Machine Identity prod ont une durée de vie limitée — vérifier l'expiration avant tout run Ansible.
