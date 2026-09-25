#!/usr/bin/env bash
# Récupère le kubeconfig du nœud K3s et met à jour les certificats du
# contexte local (utile après une rotation des certificats K3s).
#
# Usage : OVH_VPS_IP=<IP_DU_VPS> ./k8s/scripts/refresh-ovh-kubeconfig.sh
set -euo pipefail

OVH_HOST="${OVH_VPS_IP:?Définir OVH_VPS_IP (IP du VPS)}"
OVH_USER="${OVH_USER:-debian}"
OVH_PORT="${OVH_PORT:-2222}"
KUBE_CONTEXT="${KUBE_CONTEXT:-ovh-vps-k3s}"

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

echo "Récupération du kubeconfig depuis le VPS..."
ssh -p "$OVH_PORT" "$OVH_USER@$OVH_HOST" "sudo cat /etc/rancher/k3s/k3s.yaml" |
  sed "s/127.0.0.1/$OVH_HOST/g" >"$TMP_FILE"

echo "Extraction des certificats..."
NEW_CA=$(kubectl --kubeconfig "$TMP_FILE" config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
NEW_CERT=$(kubectl --kubeconfig "$TMP_FILE" config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')
NEW_KEY=$(kubectl --kubeconfig "$TMP_FILE" config view --raw -o jsonpath='{.users[0].user.client-key-data}')

echo "Mise à jour du kubeconfig local..."
kubectl config set clusters.default.certificate-authority-data "$NEW_CA"
kubectl config set clusters.default.server "https://$OVH_HOST:6443"
kubectl config set users.default.client-certificate-data "$NEW_CERT"
kubectl config set users.default.client-key-data "$NEW_KEY"

echo "Test de connexion..."
kubectl --context "$KUBE_CONTEXT" get nodes
