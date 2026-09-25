# Runbooks

Choisir le bon runbook selon le symptôme observé :

| Symptôme | Runbook |
|---|---|
| Le VPS ne répond plus / SSH impossible / panne matérielle OVH | [`rebuild-vps.md`](./rebuild-vps.md) |
| Le cluster tourne, mais les données MongoDB sont perdues, corrompues, ou un backup doit être testé/restauré | [`restore-data.md`](./restore-data.md) |

`rebuild-vps.md` ne duplique pas les étapes de `DEPLOY_PRODUCTION.md` (Terraform →
Ansible → ESO → Infisical → Traefik → ArgoCD) — il s'appuie dessus et n'ajoute que ce
qui est spécifique à un contexte incident : le choix entre restaurer un snapshot OVH ou
reconstruire from scratch, et le renvoi vers `restore-data.md` pour les données (que
`DEPLOY_PRODUCTION.md` ne couvre pas, puisqu'il part d'une base vide).
