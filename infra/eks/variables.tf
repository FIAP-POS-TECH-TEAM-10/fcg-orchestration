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
