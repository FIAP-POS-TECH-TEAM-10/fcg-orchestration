# Cluster EKS (Fase 4 — Parte 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar, em Terraform, um cluster EKS liga/desliga (`fcg-eks`) com 1 node, ALB via AWS Load Balancer Controller, Pod Identity para os 3 serviços e JWT em Secret do k8s — mais scripts `eks-up.sh`/`eks-down.sh`.

**Architecture:** Um único root module em `fcg-orchestration/infra/eks/` usando `terraform-aws-modules/eks` v20 sobre a VPC default (subnets públicas, sem NAT). Providers `helm`/`kubernetes` no mesmo state instalam o LB Controller e criam namespace, ServiceAccounts e Secret. O cluster é criado e destruído a cada sessão pelos scripts.

**Tech Stack:** Terraform ≥ 1.5 (local: 1.15), AWS provider ~> 5.95, helm ~> 2.17, kubernetes ~> 2.36, random ~> 3.6, módulos `terraform-aws-modules/eks/aws` ~> 20.37 e `terraform-aws-modules/eks-pod-identity/aws` ~> 1.12, bash (Git Bash no Windows), AWS CLI v2, kubectl.

**Spec:** `docs/superpowers/specs/2026-10-06-eks-cluster-design.md`

---

## Convenções para quem executa

- Repo: `C:\GIT\FIAP\FIAP-POS-TECH-TEAM-10\fcg-orchestration`, branch `feature/eks-cluster` (sem upstream — **não** dar push sem o usuário pedir).
- Sempre `export AWS_PROFILE=fcg-team AWS_DEFAULT_REGION=sa-east-1` antes de comandos AWS/Terraform. Conta esperada: `915153720516`.
- Não commitar `fcgames.aws.http` (alteração pré-existente que não é desta tarefa).
- "Teste" de infra aqui = `terraform fmt -check` + `terraform validate` (sem custo) e, no fim, `terraform plan` (sem custo) e um ciclo real (custo ~US$ 0,15 — **pedir confirmação ao usuário antes**).
- `terraform validate` usa `init -backend=false` para não tocar o state remoto.

## Mapa de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `infra/eks/versions.tf` | backend S3, providers e autenticação k8s/helm via `aws eks get-token` |
| `infra/eks/variables.tf` | parâmetros (região, nome, versão, node, admins, role do GitHub, namespace) |
| `infra/eks/network.tf` | VPC/subnets default + tag `kubernetes.io/role/elb` |
| `infra/eks/eks.tf` | cluster, addons, node group, access entries, namespace, policy do GitHub |
| `infra/eks/lb-controller.tf` | role Pod Identity + Helm do AWS Load Balancer Controller |
| `infra/eks/workload-iam.tf` | roles/associações Pod Identity + ServiceAccounts dos 3 serviços |
| `infra/eks/secrets.tf` | JWT aleatório → Secret `fcg-jwt` |
| `infra/eks/outputs.tf` | saídas úteis |
| `infra/eks/.gitignore` | ignora `.terraform/` e planos |
| `infra/eks/manifests/smoke-test.yaml` | nginx + Ingress ALB para validação |
| `infra/eks/README.md` | operação, custo, troubleshooting |
| `scripts/eks-up.sh` | liga o cluster |
| `scripts/eks-down.sh` | desliga o cluster sem deixar ALB órfão |
| `.gitattributes` | força LF nos `.sh` |
| `../CLAUDE.md` (fora do repo) | registrar decisões da Fase 4 parte 1 |

---

### Task 0: Limpar rascunhos

Já existem rascunhos não commitados em `infra/eks/` (versions.tf, variables.tf, network.tf, eks.tf) escritos antes do design. Eles serão sobrescritos pelas tasks abaixo.

- [ ] **Step 1: Conferir o estado**

Run: `git status -sb`
Expected: `## feature/eks-cluster`, ` M fcgames.aws.http`, `?? infra/`

- [ ] **Step 2: Remover rascunhos**

```bash
rm -rf infra/eks
mkdir -p infra/eks/manifests
```

---

### Task 1: Base — providers, variáveis, rede

**Files:**
- Create: `infra/eks/versions.tf`
- Create: `infra/eks/variables.tf`
- Create: `infra/eks/network.tf`
- Create: `infra/eks/.gitignore`

- [ ] **Step 1: Criar `infra/eks/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Mesmo bucket/tabela de lock dos serviços — key própria do cluster compartilhado.
  backend "s3" {
    bucket         = "fiap-tech-challenge-tfstate-123456-915153720516-sa-east-1-an"
    key            = "eks/terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "fiap-tech-challenge-tflocks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "fcgames"
      Component = "eks"
      ManagedBy = "terraform"
    }
  }
}

# Os providers k8s/helm pegam token via `aws eks get-token` (usa o AWS_PROFILE do shell),
# então funcionam no mesmo apply que cria o cluster.
locals {
  k8s_exec_args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.k8s_exec_args
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.k8s_exec_args
    }
  }
}
```

- [ ] **Step 2: Criar `infra/eks/variables.tf`**

```hcl
variable "aws_region" {
  type    = string
  default = "sa-east-1"
}

variable "cluster_name" {
  type    = string
  default = "fcg-eks"
}

variable "kubernetes_version" {
  type = string
  # Manter numa versão em STANDARD support — em EXTENDED o control plane passa de
  # US$ 0,10/h para US$ 0,60/h. Conferir com:
  #   aws eks describe-cluster-versions --query 'clusterVersions[].[clusterVersion,versionStatus]'
  default = "1.36"
}

variable "namespace" {
  type    = string
  default = "fcgames"
}

variable "node_instance_type" {
  type = string
  # t3.micro não serve: limite de ENI/IP = 4 pods por node (os addons já ocupam isso).
  # t3.medium aceita 17 pods por node.
  default = "t3.medium"
}

variable "node_desired_size" {
  type = number
  # 1 node = menor custo. Subir para 2 (`-var node_desired_size=2`) só se quiser mostrar
  # pods distribuídos no vídeo.
  default = 1
}

variable "admin_principal_arns" {
  type = list(string)
  # Quem pode rodar eks-up/eks-down e usar kubectl como cluster-admin.
  # Adicionar aqui o ARN de quem entrar no time (`aws sts get-caller-identity`).
  default = [
    "arn:aws:iam::915153720516:user/claude-admin",
    "arn:aws:iam::915153720516:user/daniel",
    "arn:aws:iam::915153720516:user/claudio",
    "arn:aws:iam::915153720516:user/gregori",
    "arn:aws:iam::915153720516:user/michel",
    "arn:aws:iam::915153720516:user/dev-admin",
  ]
}

variable "github_deploy_role_name" {
  type    = string
  default = "GitHubActions-ECS-Deploy-Role"
}
```

- [ ] **Step 3: Criar `infra/eks/network.tf`**

```hcl
# VPC default + subnets públicas: evita NAT Gateway (~US$ 35/mês). Os nodes recebem IP
# público (MapPublicIpOnLaunch=true nas subnets default) e puxam imagem do ECR direto.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# O AWS Load Balancer Controller só cria ALB internet-facing em subnets com essa tag.
# aws_ec2_tag marca subnets que não são deste state e remove a tag no destroy.
resource "aws_ec2_tag" "subnet_elb" {
  for_each    = toset(data.aws_subnets.default.ids)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}
```

- [ ] **Step 4: Criar `infra/eks/.gitignore`**

```gitignore
.terraform/
*.tfplan
crash.log
```

`.terraform.lock.hcl` **deve** ser commitado (fixa versões dos providers para o time).

- [ ] **Step 5: Formatar (validate só depois da Task 2, porque versions.tf referencia `module.eks`)**

Run: `cd infra/eks && terraform fmt -check; echo exit=$?`
Expected: `exit=0` (se listar arquivos, rodar `terraform fmt` e repetir)

---

### Task 2: Cluster, node group, addons e acessos

**Files:**
- Create: `infra/eks/eks.tf`

- [ ] **Step 1: Criar `infra/eks/eks.tf`**

```hcl
data "aws_caller_identity" "current" {}

data "aws_iam_role" "github_deploy" {
  name = var.github_deploy_role_name
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  cluster_endpoint_public_access = true

  # O cluster é criado e destruído a cada sessão — desliga o que sobrevive ao destroy ou
  # colide no próximo apply: chave KMS (fica 7+ dias pendente de exclusão, alias colide)
  # e log group do control plane.
  create_kms_key              = false
  cluster_encryption_config   = {}
  create_cloudwatch_log_group = false
  cluster_enabled_log_types   = []

  cluster_addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
    metrics-server         = {} # `kubectl top` e HPA (parte 2)
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]

      min_size     = 1
      max_size     = 3
      desired_size = var.node_desired_size
    }
  }

  # Acesso explícito em vez de "quem criou vira admin": várias pessoas do time rodam o
  # apply, e o creator-admin do módulo trocaria o principal a cada identidade diferente.
  enable_cluster_creator_admin_permissions = false

  access_entries = merge(
    {
      for arn in var.admin_principal_arns : "admin-${replace(arn, "/^.*\\//", "")}" => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    {
      # Pipeline dos serviços (parte 3): só edita recursos dentro do namespace da aplicação.
      github-deploy = {
        principal_arn = data.aws_iam_role.github_deploy.arn
        policy_associations = {
          edit = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
            access_scope = {
              type       = "namespace"
              namespaces = [var.namespace]
            }
          }
        }
      }
    }
  )
}

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.namespace
  }

  # Espera access entries/node: sem isso o provider k8s pode chamar a API antes de ter permissão.
  depends_on = [module.eks]
}

# `aws eks update-kubeconfig` no runner do GitHub precisa de eks:DescribeCluster.
resource "aws_iam_role_policy" "github_deploy_eks" {
  name = "fcg-eks-deploy"
  role = data.aws_iam_role.github_deploy.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster"]
      Resource = module.eks.cluster_arn
    }]
  })
}
```

- [ ] **Step 2: Init sem backend e validar**

Run:
```bash
cd infra/eks
terraform init -backend=false -input=false
terraform validate
```
Expected: `Success! The configuration is valid.`
Se `init` reclamar de conflito de versão do provider aws com o módulo, ajustar a restrição em `versions.tf` para a faixa que o erro indicar (o módulo eks 20.x exige aws `>= 5.95, < 6.0`).

- [ ] **Step 3: fmt**

Run: `terraform fmt -check; echo exit=$?`
Expected: `exit=0`

- [ ] **Step 4: Commit**

```bash
cd ../..
git add infra/eks/versions.tf infra/eks/variables.tf infra/eks/network.tf infra/eks/eks.tf infra/eks/.gitignore infra/eks/.terraform.lock.hcl
git commit -m "feat(eks): cluster fcg-eks com 1 node, addons e access entries"
```

---

### Task 3: AWS Load Balancer Controller

**Files:**
- Create: `infra/eks/lb-controller.tf`

- [ ] **Step 1: Criar `infra/eks/lb-controller.tf`**

```hcl
# Role IAM do controller via Pod Identity (policy oficial do LB Controller embutida no módulo).
module "lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.12"

  name = "${var.cluster_name}-aws-lb-controller"

  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

# Transforma objetos Ingress (ingressClassName: alb) em ALBs. Os ALBs são criados pelo
# controller, NÃO pelo Terraform — por isso o eks-down.sh apaga os Ingress antes do destroy.
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  wait       = true

  values = [yamlencode({
    clusterName  = module.eks.cluster_name
    region       = var.aws_region
    vpcId        = data.aws_vpc.default.id
    replicaCount = 1 # 1 node só — 2 réplicas ocupariam pod slot à toa
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
    }
  })]

  depends_on = [module.eks, module.lb_controller_pod_identity]
}
```

- [ ] **Step 2: Validar**

Run:
```bash
cd infra/eks
terraform init -backend=false -input=false
terraform validate && terraform fmt -check; echo exit=$?
```
Expected: `Success! The configuration is valid.` e `exit=0`

- [ ] **Step 3: Commit**

```bash
cd ../..
git add infra/eks/lb-controller.tf infra/eks/.terraform.lock.hcl
git commit -m "feat(eks): AWS Load Balancer Controller via Helm + Pod Identity"
```

---

### Task 4: IAM dos serviços (Pod Identity) e ServiceAccounts

**Files:**
- Create: `infra/eks/workload-iam.tf`

- [ ] **Step 1: Criar `infra/eks/workload-iam.tf`**

```hcl
# Equivalente às Task Roles do ECS: cada serviço tem uma role IAM, entregue ao pod pela
# ServiceAccount via EKS Pod Identity (sem access key em Secret/YAML). O worker de
# catalog/payments roda como sidecar no mesmo pod (parte 2) e usa a mesma ServiceAccount.
locals {
  account_id = data.aws_caller_identity.current.account_id

  # MassTransit auto-provisiona tópicos SNS e filas SQS na primeira conexão.
  sqs_sns_statements = [
    {
      Sid    = "Sqs"
      Effect = "Allow"
      Action = [
        "sqs:CreateQueue", "sqs:GetQueueUrl", "sqs:GetQueueAttributes", "sqs:SetQueueAttributes",
        "sqs:TagQueue", "sqs:ListQueueTags", "sqs:SendMessage", "sqs:ReceiveMessage",
        "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:PurgeQueue"
      ]
      Resource = "arn:aws:sqs:${var.aws_region}:${local.account_id}:*"
    },
    {
      Sid    = "Sns"
      Effect = "Allow"
      Action = [
        "sns:CreateTopic", "sns:GetTopicAttributes", "sns:SetTopicAttributes", "sns:TagResource",
        "sns:Subscribe", "sns:Unsubscribe", "sns:ListSubscriptionsByTopic", "sns:Publish"
      ]
      Resource = "arn:aws:sns:${var.aws_region}:${local.account_id}:*"
    },
    {
      # ListQueues/ListTopics não aceitam ARN de recurso — só "*". Sem isso o MassTransit
      # falha silenciosamente ao publicar (chama ListTopics antes de criar o tópico).
      Sid      = "ListNoResourceLevelPerms"
      Effect   = "Allow"
      Action   = ["sqs:ListQueues", "sns:ListTopics"]
      Resource = "*"
    },
  ]

  # Catalog usa DynamoDB para Jogos/Desejos (DynamoDbInitializer cria a tabela se faltar).
  dynamodb_catalog_statements = [
    {
      Sid      = "DynamoListTables"
      Effect   = "Allow"
      Action   = ["dynamodb:ListTables"]
      Resource = "*"
    },
    {
      Sid    = "DynamoTableCrud"
      Effect = "Allow"
      Action = [
        "dynamodb:CreateTable", "dynamodb:DescribeTable",
        "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem",
        "dynamodb:Query", "dynamodb:Scan",
        "dynamodb:BatchGetItem", "dynamodb:BatchWriteItem"
      ]
      Resource = [
        "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/Jogos",
        "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/Jogos/index/*",
        "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/Desejos",
        "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/Desejos/index/*"
      ]
    },
  ]

  # chave = nome da ServiceAccount no namespace da aplicação
  workloads = {
    "users-api"    = local.sqs_sns_statements
    "catalog-api"  = concat(local.sqs_sns_statements, local.dynamodb_catalog_statements)
    "payments-api" = local.sqs_sns_statements
  }
}

data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "workload" {
  for_each = local.workloads

  name               = "${var.cluster_name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "workload" {
  for_each = local.workloads

  name = "${each.key}-access"
  role = aws_iam_role.workload[each.key].id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = each.value
  })
}

resource "kubernetes_service_account_v1" "workload" {
  for_each = local.workloads

  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
}

resource "aws_eks_pod_identity_association" "workload" {
  for_each = local.workloads

  cluster_name    = module.eks.cluster_name
  namespace       = var.namespace
  service_account = each.key
  role_arn        = aws_iam_role.workload[each.key].arn
}
```

- [ ] **Step 2: Validar**

Run:
```bash
cd infra/eks
terraform validate && terraform fmt -check; echo exit=$?
```
Expected: `Success! The configuration is valid.` e `exit=0`

- [ ] **Step 3: Commit**

```bash
cd ../..
git add infra/eks/workload-iam.tf
git commit -m "feat(eks): roles Pod Identity e ServiceAccounts de users/catalog/payments"
```

---

### Task 5: Secret do JWT e outputs

**Files:**
- Create: `infra/eks/secrets.tf`
- Create: `infra/eks/outputs.tf`

- [ ] **Step 1: Criar `infra/eks/secrets.tf`**

```hcl
# JWT gerado a cada criação do cluster — nunca aparece em código/YAML ("Zero Hardcoded
# Credentials"). Os deployments da parte 2 leem via secretKeyRef { name = "fcg-jwt",
# key = "jwt-key" } → env JWT__KEY. Recriar o cluster gera chave nova (tokens antigos expiram).
resource "random_password" "jwt_key" {
  length  = 64
  special = false
}

resource "kubernetes_secret_v1" "jwt" {
  metadata {
    name      = "fcg-jwt"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  data = {
    "jwt-key" = random_password.jwt_key.result
  }
}
```

- [ ] **Step 2: Criar `infra/eks/outputs.tf`**

```hcl
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "namespace" {
  value = kubernetes_namespace_v1.app.metadata[0].name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "workload_role_arns" {
  value = { for k, r in aws_iam_role.workload : k => r.arn }
}
```

- [ ] **Step 3: Validar**

Run:
```bash
cd infra/eks
terraform validate && terraform fmt -check; echo exit=$?
```
Expected: `Success! The configuration is valid.` e `exit=0`

- [ ] **Step 4: Commit**

```bash
cd ../..
git add infra/eks/secrets.tf infra/eks/outputs.tf
git commit -m "feat(eks): Secret fcg-jwt gerado pelo Terraform e outputs"
```

---

### Task 6: Manifest de smoke test

**Files:**
- Create: `infra/eks/manifests/smoke-test.yaml`

- [ ] **Step 1: Criar `infra/eks/manifests/smoke-test.yaml`**

```yaml
# Valida o cluster sem depender dos serviços: nginx atrás de um ALB criado pelo
# AWS Load Balancer Controller. Remover com `kubectl delete -f` (ou o eks-down.sh apaga
# todos os Ingress antes do destroy).
apiVersion: apps/v1
kind: Deployment
metadata:
  name: smoke-nginx
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: smoke-nginx
  template:
    metadata:
      labels:
        app: smoke-nginx
    spec:
      containers:
        - name: nginx
          image: public.ecr.aws/nginx/nginx:alpine
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
---
apiVersion: v1
kind: Service
metadata:
  name: smoke-nginx
  namespace: default
spec:
  type: ClusterIP
  selector:
    app: smoke-nginx
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: smoke-nginx
  namespace: default
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: smoke-nginx
                port:
                  number: 80
```

- [ ] **Step 2: Validar o YAML localmente (sem cluster)**

Run: `kubectl apply --dry-run=client --validate=false -f infra/eks/manifests/smoke-test.yaml`
(se o kubectl reclamar que não alcança nenhum cluster no contexto atual, ligar o Kubernetes
do Docker Desktop ou pular este passo — o manifest é validado de verdade na Task 10)
Expected:
```
deployment.apps/smoke-nginx created (dry run)
service/smoke-nginx created (dry run)
ingress.networking.k8s.io/smoke-nginx created (dry run)
```

- [ ] **Step 3: Commit**

```bash
git add infra/eks/manifests/smoke-test.yaml
git commit -m "test(eks): manifest de smoke test (nginx + Ingress ALB)"
```

---

### Task 7: Scripts liga/desliga

**Files:**
- Create: `scripts/eks-up.sh`
- Create: `scripts/eks-down.sh`
- Create/Modify: `.gitattributes`

- [ ] **Step 1: Criar `scripts/eks-up.sh`**

```bash
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
```

- [ ] **Step 2: Criar `scripts/eks-down.sh`**

```bash
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
```

- [ ] **Step 3: Forçar LF nos .sh**

O repo roda com `core.autocrlf` no Windows: sem isso, um checkout no Windows grava os
scripts com CRLF e o bash quebra (`set: pipefail\r: invalid option`). Criar/acrescentar em
`.gitattributes` na raiz do repo:

```gitattributes
*.sh text eol=lf
```

- [ ] **Step 4: Checar sintaxe e permissão de execução**

Run:
```bash
bash -n scripts/eks-up.sh && bash -n scripts/eks-down.sh && echo OK
git add .gitattributes
git add --chmod=+x scripts/eks-up.sh scripts/eks-down.sh
```
Expected: `OK`

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(eks): scripts eks-up.sh e eks-down.sh (liga/desliga sem ALB órfão)"
```

---

### Task 8: README do infra/eks

**Files:**
- Create: `infra/eks/README.md`

- [ ] **Step 1: Criar `infra/eks/README.md`**

````markdown
# Cluster EKS — fcg-eks

Cluster Kubernetes gerenciado (AWS EKS) da Fase 4. **Liga e desliga a cada sessão** para
não gerar custo — ele não fica de pé entre sessões.

Design: [`docs/superpowers/specs/2026-10-06-eks-cluster-design.md`](../../docs/superpowers/specs/2026-10-06-eks-cluster-design.md)

## Custo

~**US$ 0,20/h** ligado (control plane US$ 0,10 + 1× t3.medium ~0,07 + ALB ~0,03).
EKS não tem free tier. **Sempre rode o `eks-down.sh` ao terminar.**

## Pré-requisitos

- AWS CLI v2, Terraform ≥ 1.5, kubectl (no Windows, rodar os scripts pelo Git Bash)
- Profile AWS da conta do time: `aws configure --profile fcg-team` (conta `915153720516`)
- Seu usuário IAM em `admin_principal_arns` (`variables.tf`) — confira com
  `aws sts get-caller-identity`

## Ligar / desligar

```bash
./scripts/eks-up.sh     # ~15-20 min — cria tudo e configura o kubectl
./scripts/eks-down.sh   # ~10-15 min — apaga Ingress/ALB e destrói o cluster
```

Para usar outro profile: `AWS_PROFILE=meu-profile ./scripts/eks-up.sh`.

## O que é criado

| Recurso | Detalhe |
|---|---|
| Cluster `fcg-eks` | Kubernetes 1.36, VPC default, subnets públicas (sem NAT) |
| Node group | 1× t3.medium (AL2023). 2 nodes: `terraform apply -var node_desired_size=2` |
| Addons | vpc-cni, coredns, kube-proxy, eks-pod-identity-agent, metrics-server |
| AWS Load Balancer Controller | Ingress `ingressClassName: alb` → ALB internet-facing |
| Namespace `fcgames` | onde os serviços rodam |
| ServiceAccounts | `users-api`, `catalog-api`, `payments-api` — cada uma com role IAM via Pod Identity (SQS/SNS; catalog também DynamoDB) |
| Secret `fcg-jwt` | chave `jwt-key`, gerada aleatoriamente a cada criação |
| Acesso | admins do time (cluster-admin); role do GitHub Actions (edit só em `fcgames`) |

Fica **fora** do cluster e sobrevive ao destroy: ECR, DynamoDB, SQS/SNS, state no S3.

## Smoke test

```bash
kubectl apply -f infra/eks/manifests/smoke-test.yaml
kubectl get ingress smoke-nginx -w        # espera aparecer o ADDRESS (2-3 min)
curl http://<ADDRESS>/                    # página do nginx
kubectl delete -f infra/eks/manifests/smoke-test.yaml
```

## Troubleshooting

| Sintoma | Causa / solução |
|---|---|
| `error: You must be logged in to the server (Unauthorized)` | seu ARN não está em `admin_principal_arns` |
| `eks-up.sh` falhou no meio | rode de novo — o Terraform continua de onde parou |
| `eks-down.sh` parou com "ainda existem ALBs" | `kubectl get ingress -A`; logs: `kubectl logs -n kube-system deploy/aws-load-balancer-controller` |
| Ingress sem ADDRESS | `kubectl describe ingress <nome>` — normalmente subnet sem tag ou controller sem permissão |
| Versão do k8s entrou em extended support (US$ 0,60/h) | subir `kubernetes_version` em `variables.tf` |
````

- [ ] **Step 2: Commit**

```bash
git add infra/eks/README.md
git commit -m "docs(eks): README de operação do cluster"
```

---

### Task 9: `terraform plan` real (sem custo)

- [ ] **Step 1: Init com backend S3 e plan**

Run:
```bash
export AWS_PROFILE=fcg-team AWS_DEFAULT_REGION=sa-east-1
cd infra/eks
terraform init -input=false -reconfigure
terraform plan -input=false -out=eks.tfplan
```
Expected: plan sem erros, terminando com `Plan: N to add, 0 to change, 0 to destroy.`
(N ≈ 60–80). Conferir na saída que aparecem: `module.eks.aws_eks_cluster.this[0]`,
`module.eks.module.eks_managed_node_group["default"]...`, 5 `aws_eks_addon`,
7 `aws_eks_access_entry` (6 admins + github), 3 `aws_ec2_tag.subnet_elb`,
3 `aws_iam_role.workload`, 3 `aws_eks_pod_identity_association.workload`,
`helm_release.aws_lb_controller`, `kubernetes_secret_v1.jwt`.

Observação: com o cluster ainda inexistente, os providers `kubernetes`/`helm` recebem
configuração "known after apply" e só criam recursos novos — o plan não precisa conectar.
Se mesmo assim o plan falhar **apenas** nesses recursos (erro de conexão/credencial do
provider k8s), registrar o erro e seguir para a Task 10: no apply o Terraform cria o
cluster antes de configurar esses providers.

- [ ] **Step 2: Apagar o plano salvo**

Run: `rm -f eks.tfplan`

---

### Task 10: Ciclo real de validação (CUSTO ~US$ 0,15 — pedir confirmação ao usuário)

- [ ] **Step 1: Confirmar com o usuário** que pode ligar o cluster agora (~40 min de ciclo).

- [ ] **Step 2: Ligar**

Run: `./scripts/eks-up.sh`
Expected: termina com `Cluster ligado.`; `kubectl get nodes` mostra 1 node `Ready`.

- [ ] **Step 3: Pods do sistema**

Run: `kubectl get pods -A`
Expected: todos `Running`: `aws-node-*`, `kube-proxy-*`, `coredns-*` (2), `eks-pod-identity-agent-*`, `metrics-server-*`, `aws-load-balancer-controller-*`.

- [ ] **Step 4: metrics-server**

Run: `kubectl top nodes`
Expected: tabela com CPU/memória do node (pode levar ~1 min após o pod ficar Running).

- [ ] **Step 5: ALB via Ingress**

Run:
```bash
kubectl apply -f infra/eks/manifests/smoke-test.yaml
kubectl get ingress smoke-nginx -w
```
Expected: em 2–3 min a coluna ADDRESS mostra `k8s-default-smokengi-....sa-east-1.elb.amazonaws.com`. Então:
Run: `curl -s http://<ADDRESS>/ | grep -o '<title>.*</title>'`
Expected: `<title>Welcome to nginx!</title>` (se der conexão recusada, aguardar mais 1–2 min o ALB ficar `active`).

- [ ] **Step 6: Secret do JWT**

Run: `kubectl get secret fcg-jwt -n fcgames -o jsonpath='{.data.jwt-key}' | base64 -d | wc -c`
Expected: `64`

- [ ] **Step 7: Pod Identity**

Run:
```bash
kubectl run pi-test -n fcgames --rm -i --restart=Never --image=public.ecr.aws/aws-cli/aws-cli:latest \
  --overrides='{"spec":{"serviceAccountName":"catalog-api"}}' -- sts get-caller-identity
```
Expected: JSON com `"Arn": "arn:aws:sts::915153720516:assumed-role/fcg-eks-catalog-api/..."`

- [ ] **Step 8: Desligar**

Run: `./scripts/eks-down.sh`
Expected: termina com `Cluster desligado.`, sem a mensagem "sobraram recursos". Depois:
```bash
aws eks list-clusters --query clusters --output text          # vazio
aws ec2 describe-tags --filters Name=key,Values=kubernetes.io/role/elb --output text   # vazio
```

- [ ] **Step 9: Registrar o resultado** de cada passo (ok/falhou + ajuste feito) na descrição do PR. Se algum passo falhou e exigiu mudança de código, commitar a correção com mensagem `fix(eks): ...` e repetir o ciclo só se a correção afetar o apply/destroy.

---

### Task 11: CLAUDE.md e PR

**Files:**
- Modify: `C:\GIT\FIAP\FIAP-POS-TECH-TEAM-10\CLAUDE.md` (fora do repo git — não entra no commit)

- [ ] **Step 1: Atualizar `CLAUDE.md`** — na seção `2.6 fcg-orchestration`, adicionar abaixo do bloco de pastas:

```markdown
**Fase 4 — Cluster EKS (`infra/eks/`)** — parte 1 da migração ECS → EKS (feito):
- Cluster `fcg-eks` (k8s 1.36, VPC default sem NAT, 1× t3.medium), conta `915153720516`, `sa-east-1`.
- **Liga/desliga por sessão** (`scripts/eks-up.sh` / `scripts/eks-down.sh`) — ~US$ 0,20/h ligado; EKS não tem free tier.
- Ingress → ALB via AWS Load Balancer Controller. `eks-down.sh` apaga os Ingress antes do destroy (senão o ALB fica órfão).
- Pod Identity: ServiceAccounts `users-api`, `catalog-api`, `payments-api` no namespace `fcgames` (criadas pelo Terraform) com as mesmas permissões das Task Roles do ECS.
- JWT: Secret `fcg-jwt` (key `jwt-key`) gerado pelo Terraform a cada criação.
- Spec/plano: `fcg-orchestration/docs/superpowers/{specs,plans}/2026-10-06-eks-cluster*`.
- Próximos: parte 2 (migrar serviços; worker como sidecar com SQLite em emptyDir; HPA × SQLite) e parte 3 (CI/CD).
```

- [ ] **Step 2: Mostrar ao usuário o resumo dos commits** (`git log --oneline origin/main..HEAD`) e **perguntar** se pode dar push e abrir o PR para `main` do `fcg-orchestration`.

- [ ] **Step 3 (após "sim"): Push e PR**

```bash
git push -u origin feature/eks-cluster
gh pr create --base main --title "Fase 4 parte 1: cluster EKS liga/desliga" --body-file <arquivo com resumo + resultados da Task 10>
```
