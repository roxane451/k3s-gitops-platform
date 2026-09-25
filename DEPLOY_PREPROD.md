# Déploiement Préprod OVH

Plan de déploiement de la préproduction.

Prérequis : variables d'environnement `OVH_VPS_IP`, `ADMIN_CIDR` et
`LETSENCRYPT_EMAIL` exportées (voir [`DEPLOY_PRODUCTION.md`](DEPLOY_PRODUCTION.md) §0).

## 1) Terraform OVH (DNS)

### 1.1) Variables

- `terraform/variables.tf` — toutes les variables disponibles
- `terraform/terraform.tfvars.example` — template à copier localement (non commité)
- Variables non sensibles à renseigner : `domain_name`, `production_public_ip` (et `preprod_public_ip` si différente)
- Les credentials OVH (`TF_VAR_ovh_app_key`, `TF_VAR_ovh_app_secret`, `TF_VAR_ovh_consumer_key`) sont injectés par `infisical run` — ne pas les mettre dans `terraform.tfvars`

### 1.2) Initialisation

```bash
cd terraform/
infisical run --env preprod -- terraform init
terraform validate
terraform fmt -check
```

### 1.3) Plan + Apply

```bash
infisical run --env preprod -- terraform plan -out=tfplan -var-file=terraform.tfvars
infisical run --env preprod -- terraform apply tfplan
```

---

## 2) Ansible — Bootstrap dépendances Galaxy

```bash
cd ansible/
ansible-playbook playbook-bootstrap.yml --tags bootstrap
```

---

## 3) Ansible — Hardening OS (premier run — port 22)

```bash
ansible-playbook -i inventories/production.yml playbook-k3s.yml \
  --tags hardening \
  -e admin_cidr="$ADMIN_CIDR" \
  -e ansible_port=22 \
  --private-key ~/.ssh/id_ed25519_platform
```

> Après cette étape : SSH bascule sur le port 2222, UFW actif.

---

## 4) Ansible — Installation K3s (port 2222)

```bash
ansible-playbook -i inventories/production.yml playbook-k3s.yml \
  --tags k3s \
  -e k3s_confirm=yes \
  --private-key ~/.ssh/id_ed25519_platform
```

---

## 5) Ansible — External Secrets Operator (ESO)

> Doit s'exécuter **après K3s** et **avant le bootstrap Infisical**.

```bash
ansible-playbook -i inventories/production.yml playbook-k3s.yml \
  --tags eso \
  --private-key ~/.ssh/id_ed25519_platform
```

---

## 6) Ansible — Bootstrap Infisical (ClusterSecretStore)

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

## 7) Traefik TLS (Let's Encrypt)

```bash
envsubst '${LETSENCRYPT_EMAIL}' < k8s/traefik/traefik-tls.yaml | kubectl apply -f -
kubectl get helmchartconfig traefik -n kube-system
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
```

---

## 8) Déploiement Helm — production

> Voir le repo `app-helm` (chart Helm applicatif, dépôt privé).

```bash
cd ../app-helm/helm
helm dependency update
helm upgrade --install app . \
  -f values-k3s-base.yaml \
  -f values-production.yaml \
  --namespace app --create-namespace
```

---

## 9) Déploiement Helm — preprod

```bash
helm upgrade --install app-preprod . \
  -f values-k3s-base.yaml \
  -f values-preprod.yaml \
  --namespace app-preprod --create-namespace
```

---

## 10) Tests post-déploiement

```bash
kubectl -n app get pods
kubectl -n app get ingress
kubectl -n app-preprod get pods
kubectl -n app-preprod get ingress
```

- API + UI disponibles sur les domaines configurés
- Vérifier Grafana : https://grafana.example.com

---

## 11) Points d'attention avant production

- TLS Let's Encrypt actif (certResolver Traefik natif — ne pas activer cert-manager en parallèle)
- Firewall OVH + admin CIDR restreint
- NetworkPolicies et HPA activés dans `values-production.yaml`
- Backup MongoDB et snapshot VPS configurés
- Rotation des clés OVH planifiée
