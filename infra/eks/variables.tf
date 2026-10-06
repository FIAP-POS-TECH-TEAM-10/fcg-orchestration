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
  # A conta está no plano FREE da AWS: o EC2 só lança tipos "free-tier-eligible"
  # (t3.micro/small, t4g.micro/small, c7i-flex.large, m7i-flex.large) — t3.medium é recusado
  # ("not eligible for Free Tier") e o node group fica preso em CREATING.
  # t3.micro não serve (4 pods/node). t3.small = 11 pods/node, 2 GB.
  default = "t3.small"
}

variable "node_desired_size" {
  type = number
  # 2× t3.small = 22 pods (addons ocupam ~10) pelo mesmo custo de 1 t3.medium.
  default = 2
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
