# Runbook — Reprise totale après perte du VPS

> `k3s-gitops-platform/runbooks/rebuild-vps.md`
> Scénario : VPS OVH de production perdu ou corrompu.
> Pour une restauration de données seule (serveur intact), voir `restore-data.md`.
>
> Ce document ne duplique pas `DEPLOY_PRODUCTION.md` — il s'appuie dessus. La
> reconstruction (Terraform → Ansible → ESO → Infisical → Traefik → ArgoCD) est déjà
> entièrement documentée là-bas ; ce runbook n'ajoute que ce qui est spécifique à un
> contexte incident : le choix de la voie de reconstruction, et la restauration des
> données (absente de `DEPLOY_PRODUCTION.md`, qui part d'une base vide).

## Sommaire

- [Étape 0 — Choisir la voie de reconstruction](#étape-0--choisir-la-voie-de-reconstruction)
- [Voie A — Restauration depuis un snapshot OVH](#voie-a--restauration-depuis-un-snapshot-ovh)
- [Voie B — Reconstruction from scratch](#voie-b--reconstruction-from-scratch)
- [Restaurer les données Mongo](#restaurer-les-données-mongo)
- [Validation finale](#validation-finale)

**Astreinte** : `<CONTACT / CANAL SLACK>`

---

## Étape 0 — Choisir la voie de reconstruction

Un snapshot VPS OVH existe pour chaque déploiement en production (`DEPLOY_PRODUCTION.md`
§1 : hebdomadaire + avant chaque déploiement). Deux voies possibles selon son ancienneté :

| | Voie A — Snapshot OVH | Voie B — From scratch |
|---|---|---|
| Quand l'utiliser | Snapshot récent (< 24-48h) disponible | Pas de snapshot exploitable, ou VPS/compte OVH totalement perdu |
| RTO | Quelques minutes (restauration image disque) | 1h30-2h (Terraform + Ansible + ESO + ArgoCD) |
| RPO | Âge du snapshot (jusqu'à 7j si hebdomadaire) | 0 — les données sont reconstruites depuis le dernier backup R2 (RPO 24h max) |
| État post-restauration | Cluster + toutes les données telles qu'au moment du snapshot | Cluster neuf, base vide → restauration Mongo obligatoire ensuite |

Le snapshot restaure *tout* (cluster + données) mais avec un RPO potentiellement plus
large que le backup Mongo. Le from-scratch a un meilleur RPO sur les données (grâce à
R2) mais un RTO plus long. **Par défaut, privilégier Voie A si un snapshot de moins de
24h existe** — sinon Voie B, avec restauration des données depuis R2 en complément
(RPO 24h max, contre potentiellement plusieurs jours pour un vieux snapshot).

---

## Voie A — Restauration depuis un snapshot OVH

Le provider Terraform `ovh/ovh` ne gère pas les snapshots de VPS : la restauration
se fait depuis l'espace client OVH (VPS → Snapshot → Restaurer) ou via l'API OVH
(`POST /vps/{serviceName}/snapshot/revert`).

Une fois le VPS restauré et accessible en SSH, revérifier l'état du cluster (le snapshot
peut être plus ancien que le dernier déploiement applicatif) :

```bash
kubectl get pods -A
kubectl get application -n argocd
make sync-prod                    # si désynchronisé depuis le snapshot
```

Si le snapshot contient déjà des données Mongo à jour, passer directement à
[Validation finale](#validation-finale). Sinon (snapshot ancien), voir
[Restaurer les données Mongo](#restaurer-les-données-mongo).

---

## Voie B — Reconstruction from scratch

Suivre **`DEPLOY_PRODUCTION.md` intégralement, sections 1 à 10** (Terraform → Ansible
hardening/K3s/ESO/Infisical → Traefik TLS → Monitoring → ArgoCD).

Avant de considérer cette étape terminée, un point que `DEPLOY_PRODUCTION.md` ne
mentionne pas puisqu'il suppose un déploiement planifié plutôt qu'un rebuild d'urgence :
**la base Mongo est vide** à l'issue de la section 10 (`seedJob.enabled: false` en prod,
donc pas même les données de seed). Passer immédiatement à l'étape suivante.

---

## Restaurer les données Mongo

Applicable après Voie B, ou après Voie A si le snapshot était ancien.

→ Exécuter **`restore-data.md`, étapes A.1 à A.4**.

Avant de déclencher `restore-data.md`, revérifier ses deux prérequis de configuration —
un cluster neuf resynchronisé depuis Git doit théoriquement les avoir, c'est le moment de
le confirmer plutôt que de le découvrir en plein incident :

```bash
helm get values app -n app | grep -A2 restoreProd
kubectl get networkpolicy -n app | grep restore
```

---

## Validation finale

Reprendre la checklist de `DEPLOY_PRODUCTION.md` §11 (pods, ingress, TLS, HPA,
ExternalSecrets), plus :

- [ ] `kubectl create job --from=cronjob/mongodb-restore-test -n app manual-$(date +%s)` passe
- [ ] Comptages par collection cohérents avec l'état attendu avant incident
- [ ] Smoke test applicatif complet
- [ ] DNS propagé si l'IP a changé (Voie B uniquement — Voie A conserve l'IP)
