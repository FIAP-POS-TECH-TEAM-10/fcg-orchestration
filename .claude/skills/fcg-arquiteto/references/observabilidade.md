# Observabilidade

Verificado em 2026-11-10. Fonte: `fcg-orchestration/k8s/eks/observability`.

- **Prometheus** (`prom/prometheus`, pod no EKS, sem Ingress): raspa `users-api.fcgames.svc:80` e
  `catalog-api.fcgames.svc:80` (`/metrics`, prometheus-net). Payments não expõe métricas. Retém 2 dias.
- **Grafana** (`grafana/grafana`, pod no EKS): `http://<alb>/grafana`, **anônimo somente leitura**,
  painel "FCGames — Observabilidade" (latência p50/p95/p99, requisições/s, erros 4xx/5xx).
  Limite de memória 512Mi (com 256Mi era OOMKilled).
- Admin do Grafana: só por `kubectl port-forward svc/grafana 3000:80 -n fcgames`, usuário `admin`,
  senha de `GRAFANA_PASSWORD`. Não logar pelo ALB (é HTTP).
- Editar o painel: altere no Grafana, exporte o JSON e atualize
  `k8s/eks/observability/fcgames-observability.json` (é provisionado a cada Ligar).
- O `eks-e2e.sh` confere o Grafana e os 2 targets do Prometheus `up`.
- Logs: JSON (Serilog) com `CorrelationId` (header `x-correlation-ID`). Ver com `kubectl logs`
  (EKS), `docker compose logs` (local) ou CloudWatch (Lambda).
- A EC2 antiga de observabilidade (Grafana/Prometheus/Zabbix) foi destruída; Zabbix saiu.
