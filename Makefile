.PHONY: restore-test restore-prod backup-test check-restore-prereqs status sync-prod \
        dashboard-backend dashboard-mongodb dashboard-frontend dashboard-loki dashboards

# ── Restauration MongoDB — voir runbooks/restore-data.md ────────────────────
# NAMESPACE=app-preprod make restore-test  pour cibler la preprod.
NAMESPACE ?= app

restore-test:
	@JOB=manual-$$(date +%s); \
	kubectl create job --from=cronjob/mongodb-restore-test -n $(NAMESPACE) $$JOB; \
	kubectl logs -n $(NAMESPACE) -f job/$$JOB -c restore-test

# Destructif (--drop réel en base). Garde-fou volontaire : refuse de s'exécuter
# sans CONFIRM=yes — pas d'accès en un mot comme les cibles ci-dessous.
# Prérequis à vérifier avant tout déclenchement : make check-restore-prereqs.
restore-prod:
ifneq ($(CONFIRM),yes)
	@echo "Restauration destructive (--drop) sur $(NAMESPACE). Relancer avec CONFIRM=yes pour confirmer."
	@echo "Vérifier d'abord : make check-restore-prereqs"
	@exit 1
endif
	@echo "⚠️  Penser à couper le backend avant restauration :"
	@echo "    kubectl scale deployment/backend -n $(NAMESPACE) --replicas=0"
	@JOB=manual-$$(date +%s); \
	kubectl create job --from=cronjob/mongodb-restore-prod -n $(NAMESPACE) $$JOB; \
	kubectl logs -n $(NAMESPACE) -f job/$$JOB -c restore

# Déclenchement manuel du backup (non destructif) — voir runbooks/restore-data.md
backup-test:
	@JOB=manual-$$(date +%s); \
	kubectl create job --from=cronjob/mongodb-backup -n $(NAMESPACE) $$JOB; \
	kubectl logs -n $(NAMESPACE) -f job/$$JOB -c backup

# Prérequis avant tout restore-prod — voir runbooks/restore-data.md §Prérequis
check-restore-prereqs:
	@echo "── database.backup.restoreProd.enabled ──"
	@helm get values app -n $(NAMESPACE) | grep -A2 restoreProd || echo "  (introuvable — vérifier le rendu Helm)"
	@echo "── NetworkPolicy restore ──"
	@kubectl get networkpolicy -n $(NAMESPACE) | grep restore || echo "  (aucune trouvée — bloquant pour restore-test/restore-prod)"

# Vue d'ensemble post-déploiement — voir DEPLOY_PRODUCTION.md §11
status:
	@echo "── Pods ──"; kubectl get pods -n $(NAMESPACE)
	@echo "── Ingress ──"; kubectl get ingress -n $(NAMESPACE)
	@echo "── ExternalSecrets ──"; kubectl get externalsecret -n $(NAMESPACE)
	@echo "── HPA ──"; kubectl get hpa -n $(NAMESPACE)
	@echo "── CronJobs ──"; kubectl get cronjob -n $(NAMESPACE)

# Sync ArgoCD manuel — automated sync volontairement désactivé en prod
sync-prod:
	argocd app sync app-production


# ── Dashboards Grafana ───────────────────────────────────────────────────────

dashboard-backend:
	kubectl create configmap grafana-dashboard-app-backend \
		-n monitoring \
		--from-file=app-backend.json=k8s/monitoring/dashboards/app-backend.json \
		--dry-run=client -o yaml \
	| yq '.metadata.labels.grafana_dashboard = "1" | .metadata.annotations.grafana_folder = "Application"' \
	> k8s/monitoring/grafana-dashboard-backend.yaml

dashboard-mongodb:
	kubectl create configmap grafana-dashboard-app-mongodb \
		-n monitoring \
		--from-file=app-mongodb.json=k8s/monitoring/dashboards/app-mongodb.json \
		--dry-run=client -o yaml \
	| yq '.metadata.labels.grafana_dashboard = "1" | .metadata.annotations.grafana_folder = "Application"' \
	> k8s/monitoring/grafana-dashboard-mongodb.yaml

dashboard-frontend:
	kubectl create configmap grafana-dashboard-app-frontend \
		-n monitoring \
		--from-file=app-frontend.json=k8s/monitoring/dashboards/app-frontend.json \
		--dry-run=client -o yaml \
	| yq '.metadata.labels.grafana_dashboard = "1" | .metadata.annotations.grafana_folder = "Application"' \
	> k8s/monitoring/grafana-dashboard-frontend.yaml

dashboard-loki:
	kubectl create configmap grafana-dashboard-app-loki \
		-n monitoring \
		--from-file=app-loki.json=k8s/monitoring/dashboards/app-loki.json \
		--dry-run=client -o yaml \
	| yq '.metadata.labels.grafana_dashboard = "1" | .metadata.annotations.grafana_folder = "Application"' \
	> k8s/monitoring/grafana-dashboard-loki.yaml


dashboards: dashboard-backend dashboard-mongodb dashboard-frontend dashboard-loki
	@echo "✔ Grafana dashboards regenerated."
