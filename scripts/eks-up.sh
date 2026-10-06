#!/usr/bin/env bash
# ==============================================================================
# FCGames — LIGA o cluster EKS (fcg-eks) a partir do Terraform em infra/eks.
#
# Custo: ~US$ 0,20/h enquanto ligado (control plane + 1 t3.medium + ALB).
# SEMPRE rode scripts/eks-down.sh ao terminar a sessão.
#
# Pré-requisitos: aws CLI v2, terraform >= 1.5, kubectl; profile AWS com acesso à
# conta do time (915153720516) e listado em admin_principal_arns (infra/eks/variables.tf).
#
# Uso: ./scripts/eks-up.sh        (~15-20 min)
# ==============================================================================
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-fcg-team}"
export AWS_DEFAULT_REGION="sa-east-1"
EXPECTED_ACCOUNT="915153720516"
CLUSTER_NAME="fcg-eks"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/infra/eks"

log() { echo "[$(date +%H:%M:%S)] $*"; }

account="$(aws sts get-caller-identity --query Account --output text)" || {
  echo "Erro: não autenticou na AWS com o profile '$AWS_PROFILE'."
  exit 1
}
if [ "$account" != "$EXPECTED_ACCOUNT" ]; then
  echo "Erro: profile '$AWS_PROFILE' aponta para a conta $account (esperado $EXPECTED_ACCOUNT)."
  exit 1
fi

cat <<'EOF'
==============================================================================
 ATENÇÃO: o cluster EKS custa ~US$ 0,20/h enquanto estiver ligado.
 Ao terminar, rode:  ./scripts/eks-down.sh
==============================================================================
EOF

log "terraform init/apply em infra/eks (o EKS leva ~15 min para ficar pronto)..."
(
  cd "$TF_DIR"
  terraform init -input=false
  terraform apply -input=false -auto-approve
)

log "Configurando kubectl para o cluster $CLUSTER_NAME..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_DEFAULT_REGION" >/dev/null

log "Nodes:"
kubectl get nodes -o wide
log "Pods:"
kubectl get pods -A

log "Cluster ligado. Lembre: ./scripts/eks-down.sh ao terminar."
