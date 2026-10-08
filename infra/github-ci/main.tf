# Permissões PERMANENTES da role do GitHub Actions ligadas ao EKS.
# NUNCA destruir — os scripts liga/desliga (scripts/eks-*.sh) não tocam neste state.
# Motivo: o pipeline dos serviços chama `aws eks describe-cluster` para saber se o cluster
# está ligado. Se esta permissão morresse junto com o cluster (como era em infra/eks), com o
# cluster desligado a resposta seria AccessDenied em vez de ResourceNotFoundException e o
# pipeline não conseguiria distinguir "desligado" de "erro".
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95"
    }
  }

  backend "s3" {
    bucket         = "fiap-tech-challenge-tfstate-123456-915153720516-sa-east-1-an"
    key            = "github-ci/terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "fiap-tech-challenge-tflocks"
    encrypt        = true
  }
}

provider "aws" {
  region = "sa-east-1"
}

locals {
  github_role_name = "GitHubActions-ECS-Deploy-Role"
  eks_cluster_arn  = "arn:aws:eks:sa-east-1:915153720516:cluster/fcg-eks"
}

# describe-cluster: checar se o cluster existe + `aws eks update-kubeconfig`.
# O acesso DENTRO do cluster (edit no namespace fcgames) continua vindo do access entry
# criado pelo Terraform do cluster (infra/eks) a cada eks-up.
resource "aws_iam_role_policy" "github_eks_describe" {
  name = "fcg-github-eks-describe"
  role = local.github_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster"]
      Resource = local.eks_cluster_arn
    }]
  })
}
