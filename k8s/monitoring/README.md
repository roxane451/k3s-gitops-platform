# k8s/monitoring

Stack de monitoring cluster — gérée par ArgoCD, indépendante du chart applicatif.

## Composants

| Fichier | Chart | Rôle |
|---|---|---|
| `application-prometheus.yaml` | kube-prometheus-stack | Prometheus + Grafana + Alertmanager |
| `application-loki.yaml` | loki-stack | Loki (logs) + Promtail (collecte) |

## Pourquoi ici et pas dans le chart applicatif ?

Ces outils sont des **opérateurs cluster** : ils installent des CRDs (PrometheusRule,
ServiceMonitor…) que le chart applicatif `app` utilise ensuite.
Mettre `kube-prometheus-stack` en dépendance Helm du chart applicatif crée un couplage
fort et empêche de partager la stack entre plusieurs apps/namespaces.

```
Infra (ArgoCD)
  ├── kube-prometheus-stack  ← installe les CRDs + Prometheus + Grafana
  └── loki-stack             ← installe Loki + Promtail

Application (chart app-helm)
  ├── ServiceMonitor         ← utilise les CRDs installées par l'infra
  └── PrometheusRule         ← idem
```

## Ordre de déploiement

```bash
# 1. Prometheus + Grafana (installe les CRDs en premier)
kubectl apply -f k8s/monitoring/application-prometheus.yaml

# 2. Attendre que les CRDs soient prêtes
kubectl get crd | grep monitoring.coreos.com   # doit lister ~12 CRDs
kubectl get pods -n monitoring -w              # attendre Running

# 3. Loki + Promtail
kubectl apply -f k8s/monitoring/application-loki.yaml

# 4. Chart applicatif (ArgoCD sync automatique)
# → les PrometheusRule et ServiceMonitor se créent sans erreur
```

## Accès Grafana

```
https://grafana.example.com
login : admin
password : voir Infisical (clé GRAFANA_ADMIN_PASSWORD)
```

## Dashboards importés (communauté)

| Dashboard | ID Grafana | Contenu |
|---|---|---|
| Kubernetes cluster | 15661 | CPU/RAM/réseau par node |
| K3s | 15759 | Métriques spécifiques K3s |
| Node Exporter | 1860 | Métriques système détaillées |
| Loki logs | 12611 | Explorer les logs par namespace |

Ces dashboards couvrent l'infra générique (node, cluster). Ils sont déclarés
directement dans `application-prometheus.yaml` (bloc `grafana.dashboards.default`)
et importés automatiquement au sync ArgoCD.

## Dashboards custom de l'application (`k8s/monitoring/dashboards/`)

Les dashboards ci-dessus ne montrent rien de spécifique à l'application :
des dashboards ont donc été écrits à la main pour visualiser
exactement les métriques utilisées par `prometheus-rules-app.yaml` (chart `app-helm`, mêmes
seuils, mêmes requêtes PromQL) :

| Fichier | Dossier Grafana | Contenu |
|---|---|---|
| `dashboards/app-backend.json` | Application | Backend Node/Express : up, req/s, taux 5xx, latence P50/P95/P99, restarts, CPU/RAM par pod |
| `dashboards/app-mongodb.json` | Application | MongoDB : up, connexions, ops/s par type, mémoire, réseau, CPU/RAM du pod |

### Comment ça se branche

Contrairement aux dashboards communautaires (importés par `gnetId` via les
values Helm), ces dashboards sont chargés via le **sidecar de découverte
Grafana** : n'importe quelle `ConfigMap` labellisée `grafana_dashboard: "1"`
dans le cluster est automatiquement détectée et importée — sans redéployer
Grafana.

```
k8s/monitoring/dashboards/*.json          ← source du dashboard (édition ici)
k8s/monitoring/grafana-dashboards-configmap.yaml
                                           ← ConfigMap qui embarque ce JSON,
                                             labellisée grafana_dashboard=1
application-prometheus.yaml
  grafana.sidecar.dashboards.enabled: true ← active la surveillance du label
```

Si tu modifies un fichier dans `dashboards/*.json` (ex: dans l'éditeur Grafana
puis export JSON), reporte le contenu dans
`grafana-dashboards-configmap.yaml` (ou régénère avec la commande `kubectl
create configmap ... --from-file` documentée en tête de ce fichier).

### Déploiement

```bash
# 1. Appliquer la mise à jour d'application-prometheus.yaml (active le sidecar dashboards)
kubectl apply -f k8s/monitoring/application-prometheus.yaml

# 2. Appliquer les ConfigMaps des dashboards custom
kubectl apply -f k8s/monitoring/grafana-dashboards-configmap.yaml

# 3. Vérifier la découverte
kubectl get configmap -n monitoring -l grafana_dashboard=1
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard --tail=50
```

Puis dans Grafana : **Dashboards → dossier "Application"** → les deux dashboards
doivent apparaître, avec les mêmes métriques et seuils que les alertes
Prometheus déjà en place.

### Point de vigilance métriques MongoDB

Le dashboard MongoDB suppose les noms de métriques standards de
`mongodb-exporter` (`mongodb_connections`, `mongodb_op_counters_total`,
`mongodb_memory`, `mongodb_network_bytes_total`, `mongodb_dbstats_dataSize`).
Selon l'image d'exporter réellement déployée dans `app-helm`, certains
noms peuvent varier légèrement — à vérifier une fois via **Prometheus →
Graph** en tapant `mongodb_` pour lister les métriques exposées, et ajuster
le JSON si besoin.
