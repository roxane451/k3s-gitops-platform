Rôle Ansible `k3d` — scope technique

Usage : `ansible-playbook playbook-k3d.yml` (cluster local de développement).

Ce README couvre uniquement le scope du rôle:
- Détection socket Docker local et configuration `DOCKER_HOST` pour `k3d`.
- Création/suppression cluster `k3d`.
- Génération de `registries.yaml` pour GHCR.
- Création du namespace Kubernetes cible via `kubernetes.core.k8s`.
- Création du secret pull image `ghcr-secret` via `kubernetes.core.k8s`.
- Déploiement Helm (`helm upgrade --install`) avec diagnostics en cas d'échec.

Variables importantes (`roles/k3d/defaults/main.yml`):
- `k3d_cluster_name`
- `k3d_namespace`
- `k3d_helm_chart_path`
- `k3d_helm_values_file`
- `k3d_registry_secret_name`
- `k3d_require_ghcr_pat`

Token GHCR local:
- Exemple: `ansible/roles/k3d/k3d.local.vars.example.yml`
- Fichier local conseillé: `ansible/roles/k3d/k3d.local.secret.yml` (non versionné)
