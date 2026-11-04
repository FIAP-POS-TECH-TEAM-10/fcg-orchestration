#!/usr/bin/env bash
# ==============================================================================
# FCGames — LIGA o cluster EKS (fcg-eks) a partir do Terraform em infra/eks.
#
# Custo: ~US$ 0,20/h enquanto ligado (control plane + 2 t3.small + ALB).
# SEMPRE rode scripts/eks-down.sh ao terminar a sessão.
#
# Pré-requisitos: aws CLI v2, terraform >= 1.5, kubectl; profile AWS com acesso à
# conta do time (915153720516) e listado em admin_principal_arns (infra/eks/variables.tf).
#
# Uso: ./scripts/eks-up.sh        (~20 min: cluster + serviços de k8s/eks)
# ==============================================================================
set -euo pipefail

# Local: usa o profile fcg-team. No GitHub Actions (OIDC) as credenciais já vêm no ambiente
# (AWS_ACCESS_KEY_ID/SECRET/SESSION_TOKEN) e um profile inexistente quebraria a autenticação.
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ -z "${AWS_PROFILE:-}" ]; then
  export AWS_PROFILE="fcg-team"
fi
export AWS_DEFAULT_REGION="sa-east-1"
EXPECTED_ACCOUNT="915153720516"
CLUSTER_NAME="fcg-eks"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT_DIR/infra/eks"

# Senhas fixas: no GitHub Actions vêm dos secrets do Environment aws-eks; local, exporte ou
# coloque no .env da raiz (ignorado pelo git). Checadas ANTES de qualquer chamada AWS.
if [ -f "$ROOT_DIR/.env" ]; then
  # Leitura literal de CHAVE=valor (NÃO usar `source`: senha com aspas, $ ou ! quebraria ou
  # executaria código). Remove o \r de um .env editado no Windows e deixa o ambiente
  # (ex.: secrets do CI) ter precedência sobre o arquivo.
  while IFS='=' read -r key value || [ -n "$key" ]; do
    key="${key%$'\r'}"; value="${value%$'\r'}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [ -n "${!key+x}" ] || export "$key=$value"
  done < "$ROOT_DIR/.env"
fi
: "${ADMIN_PASSWORD:?defina ADMIN_PASSWORD (exporte ou coloque no .env da raiz): senha do admin do app}"
: "${GRAFANA_PASSWORD:?defina GRAFANA_PASSWORD (exporte ou coloque no .env da raiz): senha do admin do Grafana}"
export TF_VAR_admin_password="$ADMIN_PASSWORD"
export TF_VAR_grafana_password="$GRAFANA_PASSWORD"

log() { echo "[$(date +%H:%M:%S)] $*"; }

# AWS CLI no Windows (Git Bash) termina linhas com \r\n — sem isso comparações e ARNs quebram.
aws() { command aws "$@" | tr -d '\r'; }

# Qualquer falha depois do apply deixa o cluster LIGADO (cobrando) — avisa sempre.
trap 'echo; echo "ERRO: o eks-up.sh falhou. Se o cluster chegou a ser criado ele está LIGADO e cobrando —"; echo "corrija e rode de novo, ou desligue com ./scripts/eks-down.sh"' ERR

account="$(aws sts get-caller-identity --query Account --output text)" || {
  echo "Erro: não autenticou na AWS com o profile '${AWS_PROFILE:-credenciais do ambiente}'."
  exit 1
}
if [ "$account" != "$EXPECTED_ACCOUNT" ]; then
  echo "Erro: profile '${AWS_PROFILE:-credenciais do ambiente}' aponta para a conta $account (esperado $EXPECTED_ACCOUNT)."
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

log "Aplicando os serviços (k8s/eks)..."
(
  cd "$ROOT_DIR"
  kubectl apply -k k8s/eks
)

for deploy in redis users-api catalog-api payments-api prometheus grafana; do
  log "Aguardando rollout de $deploy..."
  kubectl rollout status "deploy/$deploy" -n fcgames --timeout=600s
done

log "Pods:"
kubectl get pods -n fcgames -o wide

log "Aguardando o ALB do Ingress (até 5 min)..."
alb_host=""
for _ in $(seq 1 30); do
  alb_host="$(kubectl get ingress fcgames -n fcgames -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || true)"
  [ -n "$alb_host" ] && break
  sleep 10
done
if [ -z "$alb_host" ]; then
  echo "AVISO: o Ingress ainda não tem endereço. Veja: kubectl describe ingress fcgames -n fcgames"
else
  log "URL pública: http://$alb_host   (o DNS do ALB pode levar 1-2 min para responder)"
  log "Grafana (somente leitura): http://$alb_host/grafana   (alternativa: kubectl port-forward svc/grafana 3000:80 -n fcgames)"
fi

log "Cluster ligado. Lembre: ./scripts/eks-down.sh ao terminar."
