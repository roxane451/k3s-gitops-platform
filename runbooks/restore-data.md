# Runbook — Restauration de données MongoDB

> `k3s-gitops-platform/runbooks/restore-data.md`
> Scénario : perte/corruption de données MongoDB, **cluster K3s/ArgoCD/Traefik intacts**.
> Pour une reprise après perte totale du VPS, voir `rebuild-vps.md` (étape B.8 y renvoie ici).

## Sommaire

- [Prérequis](#prérequis)
- [A.1 — Valider qu'un backup est restaurable](#a1--valider-quun-backup-est-restaurable-prod-uniquement)
- [A.2 — Couper les écritures](#a2--couper-les-écritures)
- [A.3 — Restaurer dans la base réelle](#a3--restaurer-dans-la-base-réelle)
- [A.4 — Vérifier](#a4--vérifier)
- [A.5 — Remettre le backend en service](#a5--remettre-le-backend-en-service)
- [Post-mortem](#post-mortem)

---

## Prérequis

**Accès** : `kubectl` avec le contexte `~/.kube/config-ovh_vps`.

**Configuration** (à vérifier avant de déclencher quoi que ce soit) :

```bash
helm get values app -n app | grep -A2 restoreProd
# → database.backup.restoreProd.enabled: true

kubectl get networkpolicy -n app | grep restore
# → mongodb-restore-test-network-policy ET mongodb-restore-prod-network-policy
```

Si l'une des deux manque : `argocd app sync app-production` après avoir confirmé que le
chart déployé contient bien `restore-prod-job.yaml` et ses `NetworkPolicy`.

**Astreinte** : `<CONTACT / CANAL SLACK>`

**RTO mesuré en conditions réelles** (jeu de données actuel) : **9 s** pour le test de
restauration isolé, restauration réelle du même ordre de grandeur. Cette mesure grandira
avec le volume de données — à réévaluer périodiquement.

---

## A.1 — Valider qu'un backup est restaurable (prod uniquement)

```bash
kubectl create job --from=cronjob/mongodb-restore-test -n app manual-$(date +%s)
kubectl logs -n app -f job/manual-<timestamp> -c restore-test
```

Restaure le dernier backup R2 dans un `mongod` **local et éphémère** — aucun risque pour
la base réelle. **Ne pas continuer si ce job échoue** : lister les backups précédents et
en choisir un antérieur :

```bash
aws s3 ls s3://app-backups/mongodb/ --endpoint-url <r2-endpoint>
```

En preprod, `testRestore` n'est pas activé (pas de R2) — passer directement à A.2.

## A.2 — Couper les écritures

```bash
kubectl scale deployment/backend -n app --replicas=0
```

## A.3 — Restaurer dans la base réelle

```bash
kubectl create job --from=cronjob/mongodb-restore-prod -n app manual-$(date +%s)
kubectl logs -n app -f job/manual-<timestamp> -c restore
```

Ce que ce Job fait automatiquement :

1. **Snapshot de sécurité** de l'état actuel de `appdb` (`mongodump`), uploadé en
   parallèle vers `s3://app-backups/mongodb/safety-snapshots/`. Si la restauration
   s'interrompt en cours de route, ce snapshot permet de revenir en arrière plutôt que de
   rester avec une base partiellement vidée.
2. Téléchargement du dernier backup R2 (`latest.txt`)
3. `mongorestore --drop` sur `mongodb.app.svc.cluster.local:27017`
4. Vérification post-restore (comptage par collection, `--host` explicite)

Garde-fous déjà en place (rien à vérifier manuellement) : `concurrencyPolicy: Forbid`
(jamais deux `--drop` concurrents), `backoffLimit: 0` (pas de retry auto sur un échec),
double protection contre le déclenchement accidentel (`schedule` calendaire invalide
**et** `suspend: true`).

**Si la restauration échoue en cours de route** : le snapshot de sécurité pré-restore est
sur R2 (nom affiché dans les logs, sous `mongodb/safety-snapshots/`) — restaurer ce
fichier manuellement avec `mongorestore` plutôt que de relancer `restore-prod` en boucle.

## A.4 — Vérifier

La sortie de A.3 inclut déjà un comptage par collection. Pour une vérification indépendante :

```bash
kubectl exec -it mongodb-0 -n app -- mongosh \
  --host mongodb.app.svc.cluster.local:27017 \
  -u "$MONGO_USER" -p "$MONGO_PASS" --authenticationDatabase admin \
  --eval "use appdb; db.getCollectionNames().forEach(c => print(c + ': ' + db[c].countDocuments()))"
```

(`--host` explicite obligatoire — son absence a provoqué un `ECONNREFUSED
127.0.0.1:27017` lors du premier test réel.)

## A.5 — Remettre le backend en service

```bash
kubectl scale deployment/backend -n app --replicas=2   # 2 en prod (HA), 1 en preprod
```

Vérifier logs backend + smoke test avant de clore l'incident.

---

## Post-mortem

1. Cause racine, heure de détection, heure de résolution, RTO réel observé
2. Comparer au RTO mesuré ci-dessus — signaler tout écart significatif
3. Si un backup s'est révélé non restaurable (§A.1) : incident distinct sur le CronJob de
   backup (`kubectl get cronjob -n app`, `make backup-test`)
4. Si le snapshot de sécurité pré-restore (§A.3) a dû être utilisé : documenter pourquoi
   `restore-prod` s'est interrompu — c'est un signal à creuser avant de refaire confiance
   au pipeline
