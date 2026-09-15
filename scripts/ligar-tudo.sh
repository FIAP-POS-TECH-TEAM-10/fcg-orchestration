#!/usr/bin/env bash
# ==============================================================================
# FCGames — religa toda a infra da AWS que foi pausada pra economizar custo.
#
# O que faz:
#   1. Escala as 3 ASGs (users/catalog/payments) de volta pra 1 instância EC2
#   2. Escala os 3 serviços ECS de volta pra 1 task
#   3. Liga a EC2 de observabilidade (Grafana/Prometheus/Zabbix)
#   4. Espera tudo ficar saudável e mostra os links prontos pra usar
#
# Pré-requisitos:
#   - AWS CLI instalado (aws --version)
#   - Acesso configurado à conta do time (915153720516), região sa-east-1
#     Rode `aws configure --profile fcg-team` uma vez se ainda não tiver, ou
#     ajuste a variável AWS_PROFILE abaixo se seu profile tiver outro nome.
#
# Como rodar:
#   chmod +x ligar-tudo.sh
#   ./ligar-tudo.sh
#
# Demora uns 3-5 minutos no total (EC2 + ECS levam tempo pra subir e ficar
# saudável). O script fica esperando e avisa quando cada coisa fica pronta.
# ==============================================================================

set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-fcg-team}"
export AWS_DEFAULT_REGION="sa-east-1"

# --- Recursos conhecidos (não mudam entre execuções) -------------------------
ASGS=(fcg-users-service-asg fcg-catalog-service-asg fcg-payments-service-asg)
declare -A CLUSTER_OF_SERVICE=(
  [fcg-users-service]=fcg-users-cluster
  [fcg-catalog-service]=fcg-catalog-cluster
  [fcg-payments-service]=fcg-payments-cluster
)
OBS_INSTANCE_ID="i-083fafb773752dfba"

USERS_URL="https://1ipnp7vn16.execute-api.sa-east-1.amazonaws.com"
CATALOG_URL="https://e0wcpyuyna.execute-api.sa-east-1.amazonaws.com"
PAYMENTS_URL="https://ke768yj141.execute-api.sa-east-1.amazonaws.com"

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "Usando AWS profile: $AWS_PROFILE"
aws sts get-caller-identity --query 'Account' --output text > /dev/null || {
  echo "Erro: não consegui autenticar na AWS com o profile '$AWS_PROFILE'."
  echo "Confere se já rodou 'aws configure --profile $AWS_PROFILE' com as credenciais certas."
  exit 1
}

# --- 1. ASGs: min=1, desired=1 ------------------------------------------------
log "Escalando as 3 ASGs de volta pra 1 instância..."
for asg in "${ASGS[@]}"; do
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$asg" \
    --min-size 1 --desired-capacity 1 \
    >/dev/null
  log "  $asg -> min=1 desired=1"
done

# --- 2. EC2 de observabilidade -------------------------------------------------
log "Ligando a EC2 de observabilidade ($OBS_INSTANCE_ID)..."
aws ec2 start-instances --instance-ids "$OBS_INSTANCE_ID" >/dev/null || \
  log "  (aviso: start-instances falhou — talvez já esteja rodando, seguindo em frente)"

# --- 3. Serviços ECS: desired=1 ------------------------------------------------
# Espera as EC2 das ASGs terminarem de registrar no cluster antes de escalar o
# serviço, senão o ECS fica tentando agendar task sem capacidade disponível.
log "Esperando as instâncias das ASGs registrarem nos clusters ECS..."
for service in "${!CLUSTER_OF_SERVICE[@]}"; do
  cluster="${CLUSTER_OF_SERVICE[$service]}"
  for _ in $(seq 1 30); do
    count=$(aws ecs describe-clusters --clusters "$cluster" \
      --query 'clusters[0].registeredContainerInstancesCount' --output text)
    [ "$count" -ge 1 ] && break
    sleep 10
  done
  log "  $cluster: $count instância(s) registrada(s)"
done

log "Escalando os 3 serviços ECS de volta pra 1 task..."
for service in "${!CLUSTER_OF_SERVICE[@]}"; do
  cluster="${CLUSTER_OF_SERVICE[$service]}"
  aws ecs update-service --cluster "$cluster" --service "$service" \
    --desired-count 1 >/dev/null
  log "  $service -> desired=1"
done

# --- 4. Espera tudo ficar saudável --------------------------------------------
log "Esperando os serviços ECS ficarem estáveis (pode levar 1-2 min)..."
for service in "${!CLUSTER_OF_SERVICE[@]}"; do
  cluster="${CLUSTER_OF_SERVICE[$service]}"
  aws ecs wait services-stable --cluster "$cluster" --services "$service" || \
    log "  (aviso: $service não ficou estável a tempo — confira manualmente)"
done

check_health() {
  local name="$1" url="$2"
  for _ in $(seq 1 12); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || echo "000")
    [ "$code" == "200" ] && { log "  $name: OK (200)"; return 0; }
    sleep 5
  done
  log "  $name: ainda não respondeu 200 (último código: $code) — pode precisar de mais alguns minutos"
}

log "Checando health checks..."
check_health "UsersAPI    " "$USERS_URL/health"
check_health "CatalogAPI  " "$CATALOG_URL/health"
check_health "PaymentsAPI " "$PAYMENTS_URL/health"

echo ""
echo "=============================================================================="
echo " Tudo religado! Links:"
echo "=============================================================================="
echo "  UsersAPI     -> $USERS_URL/health"
echo "  CatalogAPI   -> $CATALOG_URL/health"
echo "  PaymentsAPI  -> $PAYMENTS_URL/health"
echo ""
echo "  Grafana      -> http://<IP da EC2 de observabilidade>:3000"
echo "  Prometheus   -> http://<IP da EC2 de observabilidade>:9090"
echo "  (o IP muda toda vez que a EC2 liga — pega o atual com:)"
echo "    aws ec2 describe-instances --instance-ids $OBS_INSTANCE_ID \\"
echo "      --query 'Reservations[0].Instances[0].PublicIpAddress' --output text"
echo "=============================================================================="
