# Como acessar cada recurso

Verificado em 2026-11-10. Região sempre **São Paulo (`sa-east-1`)**; em outra região o console aparece vazio.

## Quem acessa o quê

| Acesso | Como se obtém |
|---|---|
| Console AWS | usuário IAM na conta `915153720516` (**IAM user sign in**, não root); peça a um admin do time |
| AWS CLI / scripts | `aws configure --profile fcg-team` com chaves do seu usuário IAM |
| kubectl no EKS | seu ARN em `admin_principal_arns` (`infra/eks/variables.tf`); o `eks-up.sh` já roda `aws eks update-kubeconfig --name fcg-eks --region sa-east-1`. Quem só ligou pelo GitHub: rode esse comando com o profile |
| Botões Ligar/Desligar | permissão de escrita no `fcg-orchestration` |
| Secrets do GitHub (`aws-eks`) | admin do repositório `fcg-orchestration` |

## Recursos

| Recurso | Onde | Precisa do cluster ligado? |
|---|---|---|
| API (todas as rotas) | `http://<ALB>/...`; o ALB aparece no resumo do **Ligar** e em `kubectl get ingress -n fcgames` (muda a cada Ligar) | sim |
| Grafana | `http://<ALB>/grafana` (leitura); admin via port-forward (`observabilidade.md`) | sim |
| Pods e logs | `kubectl get pods -n fcgames`; `kubectl logs -n fcgames deploy/catalog-api -c worker -f` | sim |
| Cluster no console | EKS → Clusters → `fcg-eks` (Resources, Compute, Add-ons, Access → Pod Identity) | sim |
| Load balancer | EC2 → Load Balancers → `k8s-fcgames-*` (Listeners → Rules; Target Groups → saúde dos pods) | sim |
| Imagens | ECR → `fcg-users-service` / `fcg-catalog-service` / `fcg-payments-service` | não |
| Jogos e desejos | DynamoDB → Tables → `Jogos` / `Desejos` → Explore items | não |
| Eventos | SNS → Topics (`FCGames_IntegrationEvents-*`); SQS → Queues (mensagens e filas `_error`/`-dlq`) | não |
| Notificações (AWS) | Lambda → `fiap-fcgames-notifications-lambda` → Monitor → View CloudWatch logs | não |
| Estado do Terraform | S3 → `fiap-tech-challenge-tfstate-…` (só olhar; nunca apagar) | não |
| Custos | Billing → Free Tier / Cost Explorer | não |
| Pipelines e Trivy | GitHub → Actions de cada repo; Security → Code scanning | não |
| Local (compose) | APIs em `localhost:5001-5003`, Swagger do users em `/swagger`, RabbitMQ em `localhost:15672`, DynamoDB local em `localhost:8000` | — |

## Logins da aplicação

- Admin do app: `admin@fcgames.com`, senha = `ADMIN_PASSWORD` (secret do GitHub no EKS; `.env` local).
- Usuário comum: `POST /usuarios` cria na hora (ver `fcgames.http` / `fcgames.eks.http`).
- O token vai no header `Authorization: Bearer <token>`.
