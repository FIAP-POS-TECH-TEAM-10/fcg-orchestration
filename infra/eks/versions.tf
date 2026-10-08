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
