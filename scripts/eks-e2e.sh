#!/usr/bin/env bash
# ==============================================================================
# FCGames — teste ponta a ponta no EKS, pelo ALB público:
#   cadastro → biblioteca criada (evento via SNS/SQS) → login → compra aprovada
#   (preço <= 100) → compra rejeitada (preço > 100) → pagamento consultado.
#
# Uso: ./scripts/eks-e2e.sh [URL_BASE]
#   Sem argumento, descobre a URL pelo Ingress "fcgames" (precisa do kubectl apontando
#   para o fcg-eks — o eks-up.sh já configura).
# ==============================================================================
set -euo pipefail

PY=""
for c in python3 python; do
  if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import json' >/dev/null 2>&1; then PY="$c"; break; fi
done
[ -n "$PY" ] || { echo "Erro: precisa de Python 3 (python3 ou python) no PATH."; exit 1; }
BASE="${1:-}"
if [ -z "$BASE" ]; then
  host="$(kubectl get ingress fcgames -n fcgames -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
  [ -n "$host" ] || { echo "Erro: Ingress fcgames sem endereço."; exit 1; }
  BASE="http://$host"
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }
fail() { echo "FALHOU: $*"; exit 1; }
# Lê JSON do stdin e avalia uma expressão Python sobre ele (variável d).
jq_py() { "$PY" -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

# Senha do admin: do ambiente (CI / .env exportado) ou, se faltar, do Secret fcg-admin do cluster.
if [ -z "${ADMIN_PASSWORD:-}" ]; then
  ADMIN_PASSWORD="$(kubectl get secret fcg-admin -n fcgames -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
fi
[ -n "${ADMIN_PASSWORD:-}" ] || { echo "Erro: defina ADMIN_PASSWORD ou aponte o kubectl para o cluster (Secret fcg-admin)."; exit 1; }
export ADMIN_PASSWORD
# Corpo montado em Python: senha com aspas, \$ ou ! não pode quebrar o JSON nem o shell.
admin_login_body="$("$PY" -c 'import json,os; print(json.dumps({"email":"admin@fcgames.com","senha":os.environ["ADMIN_PASSWORD"]}))')"

# Repete um GET até a expressão Python retornar "ok" (eventos são assíncronos).
wait_for() {
  local url="$1" expr="$2" token="$3" body
  for _ in $(seq 1 30); do
    body="$(curl -m 10 -s -H "Authorization: Bearer $token" "$url" || true)"
    if [ -n "$body" ] && [ "$(echo "$body" | jq_py "$expr" 2>/dev/null || true)" = "ok" ]; then
      echo "$body"
      return 0
    fi
    sleep 2
  done
  return 1
}

log "Base: $BASE"

# Logo após o eks-up o ALB acabou de nascer: o DNS leva ~1-3 min para resolver (curl → 000).
# Espera o login do admin seed responder 200 antes de começar (até 5 min).
log "0) Aguardando o ALB responder (até 5 min)..."
for _ in $(seq 1 30); do
  code="$(curl -s -m 5 -o /dev/null -w '%{http_code}' -X POST "$BASE/usuarios/login" \
    -H 'Content-Type: application/json' -d "$admin_login_body" || true)"
  [ "$code" = "200" ] && break
  sleep 10
done
[ "$code" = "200" ] || fail "ALB não respondeu 200 em 5 min (último código: $code)"

email="e2e-$(date +%s)@teste.com"
senha="E2e@$(date +%s)" # usuário descartável deste run; não é credencial de nada

log "1) Cadastro ($email)"
cadastro="$(curl -m 10 -sf -X POST "$BASE/usuarios" -H 'Content-Type: application/json' \
  -d "{\"nome\":\"e2e\",\"email\":\"$email\",\"senha\":\"$senha\"}")" || fail "POST /usuarios"
uid="$(echo "$cadastro" | jq_py "d['id']")" || fail "id ausente na resposta do cadastro"

log "2) Login"
token="$(curl -m 10 -sf -X POST "$BASE/usuarios/login" -H 'Content-Type: application/json' \
  -d "{\"email\":\"$email\",\"senha\":\"$senha\"}" | jq_py "d['token']")" || fail "POST /usuarios/login"

log "3) Biblioteca criada pelo worker do catalog (UsuarioCriadoEvento)"
wait_for "$BASE/biblioteca/$uid" "'ok' if d['usuarioId'] else ''" "$token" >/dev/null \
  || fail "biblioteca de $uid não apareceu em 60 s"

log "4) Escolhendo jogos (preço <= 100 e > 100)"
jogos="$(curl -m 10 -sf -H "Authorization: Bearer $token" "$BASE/jogos")" || fail "GET /jogos"
barato="$(echo "$jogos" | jq_py "next((j['id'] for j in d if 0 < j['preco'] <= 100), '')")" || fail "parse de /jogos"
[ -n "$barato" ] || fail "nenhum jogo com preço <= 100 em /jogos"
caro="$(echo "$jogos" | jq_py "next((j['id'] for j in d if j['preco'] > 100), '')")" || fail "parse de /jogos"
[ -n "$caro" ] || fail "nenhum jogo com preço > 100 em /jogos"

log "5) Compra aprovada ($barato)"
pedido_ok="$(curl -m 10 -sf -X POST "$BASE/compras" -H "Authorization: Bearer $token" \
  -H 'Content-Type: application/json' -d "{\"jogoId\":\"$barato\"}" | jq_py "d['orderId']")" || fail "POST /compras (barato)"
wait_for "$BASE/compras/$pedido_ok" "'ok' if d['status']=='Aprovado' else ''" "$token" >/dev/null \
  || fail "pedido $pedido_ok não ficou Aprovado"

log "6) Compra rejeitada ($caro)"
pedido_nok="$(curl -m 10 -sf -X POST "$BASE/compras" -H "Authorization: Bearer $token" \
  -H 'Content-Type: application/json' -d "{\"jogoId\":\"$caro\"}" | jq_py "d['orderId']")" || fail "POST /compras (caro)"
wait_for "$BASE/compras/$pedido_nok" "'ok' if d['status']=='Rejeitado' else ''" "$token" >/dev/null \
  || fail "pedido $pedido_nok não ficou Rejeitado"

log "7) Pagamento do pedido aprovado"
wait_for "$BASE/pagamentos/$pedido_ok" "'ok' if d['status']=='Aprovado' else ''" "$token" >/dev/null \
  || fail "pagamento de $pedido_ok não está Aprovado"

log "8) Jogo na biblioteca"
wait_for "$BASE/biblioteca/$uid" "'ok' if any(j['jogoId']=='$barato' for j in d['jogos']) else ''" "$token" >/dev/null \
  || fail "jogo $barato não está na biblioteca"

log "9) Grafana (somente leitura, pelo ALB em /grafana)"
gcode=""
for _ in $(seq 1 30); do
  gcode="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$BASE/grafana/api/health" || true)"
  [ "$gcode" = "200" ] && break
  sleep 10
done
[ "$gcode" = "200" ] || fail "GET /grafana/api/health não deu 200 (último código: $gcode)"
curl -m 10 -sf "$BASE/grafana/api/search?query=" | grep -q 'fcgames-observability' \
  || fail "dashboard fcgames-observability não aparece em /grafana/api/search (acesso anônimo Viewer / provisionamento)"

log "10) Prometheus raspando users-api e catalog-api (targets up)"
targets_ok=""
for _ in $(seq 1 12); do
  alvos="$(kubectl exec -n fcgames deploy/prometheus -- wget -qO- http://localhost:9090/api/v1/targets 2>/dev/null || true)"
  if [ -n "$alvos" ] && [ "$(echo "$alvos" | jq_py "'ok' if {t['labels']['job'] for t in d['data']['activeTargets'] if t['health']=='up'} >= {'fcg-users-service','fcg-catalog-service'} else ''" 2>/dev/null || true)" = "ok" ]; then
    targets_ok=1; break
  fi
  sleep 5
done
[ -n "$targets_ok" ] || fail "Prometheus sem os jobs fcg-users-service e fcg-catalog-service com health=up em 60 s"

log "OK — fluxo completo passou (aprovado: $pedido_ok, rejeitado: $pedido_nok)"
