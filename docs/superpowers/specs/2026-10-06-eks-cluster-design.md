# Fase 4 — Parte 1: Cluster EKS (design)

**Data:** 2026-10-06
**Responsável:** Daniel
**Status:** aprovado no brainstorming, aguardando plano de implementação

## Contexto

O PDF da Fase 4 exige Kubernetes **gerenciado** (EKS/AKS/GKE/OKE), registry nativo (ECR),
exposição via Load Balancer ou Ingress, rolling update e zero credenciais hardcoded.
Hoje o FCGames roda em **ECS on EC2** (um cluster ECS + 1 `t3.micro` por serviço) — isso
não é Kubernetes e não atende o requisito.

A migração foi dividida em 3 sub-projetos, cada um com spec → plano → implementação:

1. **Cluster EKS** ← este documento
2. Migração dos serviços (manifests users/catalog/payments, worker sidecar, Ingress com paths,
   Redis no cluster, HPA, remoção do ECS/API Gateways)
3. CI/CD (build, teste, Trivy, push ECR, rolling update no EKS para users e catalog)

## Restrições

- **Custo mínimo.** EKS não tem free tier (control plane US$ 0,10/h). O cluster é
  **criado e destruído a cada sessão** (`terraform apply` / `terraform destroy`). Nada fica
  ligado entre sessões.
- **Sem proteção automática** contra esquecer o cluster ligado (sem Budget, sem destroy
  agendado) — risco aceito pelo time; mitigado por aviso de custo nos scripts.
- Conta AWS do time: `915153720516`, região `sa-east-1`, profile local `fcg-team`.
- SQLite continua **efêmero** (decisão do time; impacto tratado na parte 2).

## Decisões

| Tema | Decisão | Alternativas descartadas |
|---|---|---|
| Ferramenta | Terraform com módulo `terraform-aws-modules/eks` (~> 20.37) + providers helm/kubernetes no mesmo state | recursos `aws_eks_*` à mão (mais código); eksctl (foge do padrão Terraform do time); EKS Auto Mode (custo imprevisível) |
| Local | `fcg-orchestration/infra/eks/`, state `s3://fiap-tech-challenge-tfstate-123456-915153720516-sa-east-1-an/eks/terraform.tfstate`, lock `fiap-tech-challenge-tflocks` | repo novo |
| Cluster | 1 cluster compartilhado `fcg-eks`, Kubernetes **1.36** (standard support até 2027-08; extended custa US$ 0,60/h) | cluster por serviço |
| Rede | VPC default, 3 subnets públicas (sa-east-1a/b/c), sem NAT Gateway | VPC dedicada + NAT (~US$ 35/mês) |
| Nodes | 1 managed node group, **1× `t3.medium`** on-demand, AL2023; min 1 / max 3; `desired` em variável | 2× t3.medium; Spot (interrupção na gravação) |
| Exposição | AWS Load Balancer Controller (Helm, 1 réplica) → 1 ALB por Ingress | ingress-nginx (fim de suporte); Service LoadBalancer por serviço (3× custo) |
| Segredos | Terraform gera JWT aleatório (64 chars) → `kubernetes_secret` `fcg-jwt` no namespace `fcgames` | External Secrets + Secrets Manager (complexidade para 1 segredo); Secret criado pelo pipeline |
| IAM dos apps | Pod Identity: 1 role por serviço ligada às ServiceAccounts `users-api`, `catalog-api`, `payments-api` | access key em Secret; permissões na role do node |
| Acesso humano | Access entries `AmazonEKSClusterAdminPolicy` para `claude-admin`, `daniel`, `claudio`, `gregori`, `michel`, `dev-admin` | só o responsável |
| Acesso CI | Role `GitHubActions-ECS-Deploy-Role`: `AmazonEKSEditPolicy` só no namespace `fcgames` + inline `eks:DescribeCluster` | cluster-admin |
| Desligados | KMS do cluster (chave fica 7+ dias pendente, colide no próximo apply) e logs do control plane no CloudWatch | — |

## Componentes

```
fcg-orchestration/
  infra/eks/
    versions.tf        backend S3, providers aws/helm/kubernetes/random, exec `aws eks get-token`
    variables.tf       região, nome, versão k8s, tipo/qtd de node, admins, role do GitHub
    network.tf         data VPC/subnets default + aws_ec2_tag kubernetes.io/role/elb=1
    eks.tf             module "eks", addons, node group, access entries, namespace fcgames,
                       inline policy eks:DescribeCluster na role do GitHub
    lb-controller.tf   role Pod Identity + helm_release aws-load-balancer-controller
    workload-iam.tf    roles Pod Identity por serviço (for_each) + associações + ServiceAccounts
                       (criadas pelo Terraform; a parte 2 só referencia pelo nome)
    secrets.tf         random_password + kubernetes_secret fcg-jwt
    outputs.tf         cluster_name, comando update-kubeconfig, ARNs das roles
    manifests/
      smoke-test.yaml  nginx Deployment + Service + Ingress (ALB) para validação
    README.md          como ligar/desligar, custo, troubleshooting
  scripts/
    eks-up.sh
    eks-down.sh
```

**Addons EKS:** `vpc-cni` e `eks-pod-identity-agent` (antes do node), `kube-proxy`,
`coredns`, `metrics-server` (habilita `kubectl top` e o HPA da parte 2).

**Permissões por serviço** (copiadas das Task Roles do ECS atual):

| ServiceAccount | Permissões |
|---|---|
| `users-api` | SQS/SNS (Create/Get/Set/Send/Receive/Delete/Subscribe/Publish na conta+região) + `sqs:ListQueues`, `sns:ListTopics` em `*` |
| `catalog-api` | o mesmo SQS/SNS + DynamoDB nas tabelas `Jogos`, `Desejos` (e índices) + `dynamodb:ListTables` em `*` |
| `payments-api` | o mesmo SQS/SNS |

O worker de catalog/payments roda como sidecar no mesmo pod (parte 2), então usa a mesma
ServiceAccount. Permissões de OpenSearch serão adicionadas à role do catalog quando a parte
de busca definir o domínio.

## Fluxo liga/desliga

**`scripts/eks-up.sh`** (~15–20 min)
1. Valida a identidade AWS (`aws sts get-caller-identity`) e imprime aviso de custo
   (~US$ 0,20/h, "rode eks-down.sh ao terminar").
2. `terraform init` + `apply` em `infra/eks`.
3. `aws eks update-kubeconfig --name fcg-eks --region sa-east-1`.
4. Mostra `kubectl get nodes` e `kubectl get pods -A`.
5. (Parte 2 adiciona o deploy dos serviços aqui.)

**`scripts/eks-down.sh`** (~10–15 min)
1. `kubectl delete ingress --all -A` — o ALB é criado pelo controller, não pelo Terraform;
   se o controller for destruído antes, o ALB fica órfão cobrando e trava os security groups.
2. Espera até nenhum load balancer com nome `k8s-*` existir (convenção de nome do
   LB Controller; timeout 5 min; se estourar, aborta sem destroy e mostra o que sobrou).
3. `terraform destroy` em `infra/eks`.
4. Checagem final: lista ALBs/target groups `k8s-*` remanescentes e imprime o comando
   para removê-los.

Os dois scripts usam `AWS_PROFILE=${AWS_PROFILE:-fcg-team}` e `set -euo pipefail`, em bash
(como `scripts/ligar-tudo.sh`; no Windows via Git Bash).

**Sobrevive ao destroy:** ECR, DynamoDB, SQS/SNS, state S3 (fora deste Terraform).
**Perdido a cada destroy:** SQLite dos pods (já efêmero) e o JWT (regenerado — tokens
antigos param de valer).

**Falhas:** `apply` falhou → rodar `eks-up.sh` de novo (idempotente). `destroy` falhou →
script para com o erro; rodar `eks-down.sh` de novo. Nunca apagar o state.

## Custo estimado (sa-east-1, por hora ligada)

| Item | US$/h |
|---|---|
| Control plane EKS | 0,10 |
| 1× t3.medium | ~0,07 |
| ALB (quando houver Ingress) | ~0,03 |
| IPs públicos IPv4 | ~0,01 |
| **Total** | **~0,20** |

40 h ligadas no total ≈ US$ 8.

## Validação

Antes de gastar: `terraform fmt -check`, `terraform validate`, `terraform plan`.

Ciclo de teste real (um único ciclo up → testes → down):

1. `eks-up.sh` termina sem erro.
2. `kubectl get nodes` → 1 node `Ready`.
3. `kubectl get pods -A` → coredns, aws-node, kube-proxy, eks-pod-identity-agent,
   metrics-server, aws-load-balancer-controller em `Running`.
4. `kubectl top nodes` responde.
5. `kubectl apply -f infra/eks/manifests/smoke-test.yaml` → `kubectl get ingress` mostra o
   hostname do ALB → `curl http://<alb>/` retorna a página do nginx.
6. `kubectl get secret fcg-jwt -n fcgames` existe.
7. Pod temporário com ServiceAccount `catalog-api` no namespace `fcgames` executa
   `aws sts get-caller-identity` e recebe a role do catalog.
8. `eks-down.sh` termina; `aws eks list-clusters` vazio; nenhum ALB `k8s-*`;
   tags `kubernetes.io/role/elb` removidas das subnets.

## Definição de pronto

- Os 8 passos de validação passam em um mesmo ciclo.
- PR para `main` do `fcg-orchestration` com `infra/eks/`, `scripts/eks-up.sh`,
  `scripts/eks-down.sh`.
- `infra/eks/README.md` explica ligar/desligar, custo e troubleshooting.
- `CLAUDE.md` (raiz do workspace) atualizado com as decisões desta parte.

## Fora do escopo (partes 2 e 3)

Manifests dos serviços, Ingress real com paths, Redis no cluster, HPA (e o conflito
HPA × SQLite efêmero — cada réplica teria seu próprio banco), remoção do ECS/API Gateways,
pipelines de CI/CD, permissões de OpenSearch.
