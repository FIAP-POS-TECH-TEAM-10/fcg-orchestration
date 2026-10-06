#!/usr/bin/env bash
# ==============================================================================
# FCGames — DESLIGA (destrói) o cluster EKS (fcg-eks) para não gerar custo.
#
# Ordem importa: os ALBs são criados pelo AWS Load Balancer Controller, não pelo
# Terraform. Se o destroy remover o controller antes, o ALB fica órfão (cobrando) e
# trava a remoção dos security groups. Por isso: apaga Ingress → espera ALBs sumirem
# → terraform destroy → confere sobras.
#
# Sobrevive: ECR, DynamoDB, SQS/SNS, state no S3. Perde: SQLite dos pods e o JWT.
#
# Uso: ./scripts/eks-down.sh        (~10-15 min)
# ==============================================================================
set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-fcg-team}"
export AWS_DEFAULT_REGION="sa-east-1"
EXPECTED_ACCOUNT="915153720516"
CLUSTER_NAME="fcg-eks"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/infra/eks"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# ALBs/target groups criados pelo controller sempre têm nome "k8s-...".
k8s_albs() {
  aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?starts_with(LoadBalancerName, 'k8s-')].LoadBalancerArn" --output text
}
k8s_target_groups() {
  aws elbv2 describe-target-groups \
    --query "TargetGroups[?starts_with(TargetGroupName, 'k8s-')].TargetGroupArn" --output text
}

account="$(aws sts get-caller-identity --query Account --output text)" || {
  echo "Erro: não autenticou na AWS com o profile '$AWS_PROFILE'."
  exit 1
}
if [ "$account" != "$EXPECTED_ACCOUNT" ]; then
  echo "Erro: profile '$AWS_PROFILE' aponta para a conta $account (esperado $EXPECTED_ACCOUNT)."
  exit 1
fi

# --- 1. Apagar Ingress (o controller remove os ALBs) -----------------------------
if aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_DEFAULT_REGION" >/dev/null
  log "Apagando todos os Ingress (o LB Controller remove os ALBs)..."
  kubectl delete ingress --all -A --timeout=180s
else
  log "Cluster $CLUSTER_NAME não existe — pulando limpeza de Ingress."
fi

# --- 2. Esperar ALBs sumirem (até 5 min) -----------------------------------------
log "Aguardando ALBs k8s-* serem removidos..."
for _ in $(seq 1 30); do
  [ -z "$(k8s_albs)" ] && break
  sleep 10
done
remaining="$(k8s_albs)"
if [ -n "$remaining" ]; then
  echo "Erro: ainda existem ALBs do cluster após 5 min — NÃO vou rodar o destroy."
  echo "ALBs restantes: $remaining"
  echo "Verifique 'kubectl get ingress -A' e os logs do aws-load-balancer-controller."
  exit 1
fi

# --- 3. Destroy ------------------------------------------------------------------
log "terraform destroy em infra/eks..."
(
  cd "$TF_DIR"
  terraform init -input=false
  terraform destroy -input=false -auto-approve
)

# --- 4. Checagem final -----------------------------------------------------------
log "Checando sobras..."
leftover_albs="$(k8s_albs)"
leftover_tgs="$(k8s_target_groups)"
clusters="$(aws eks list-clusters --query 'clusters' --output text)"

if [ -n "$leftover_albs" ] || [ -n "$leftover_tgs" ]; then
  echo "ATENÇÃO: sobraram recursos de load balancer. Remova com:"
  for arn in $leftover_albs; do echo "  aws elbv2 delete-load-balancer --load-balancer-arn $arn"; done
  for arn in $leftover_tgs; do echo "  aws elbv2 delete-target-group --target-group-arn $arn"; done
fi
log "Clusters EKS na conta: ${clusters:-(nenhum)}"
log "Cluster desligado."
