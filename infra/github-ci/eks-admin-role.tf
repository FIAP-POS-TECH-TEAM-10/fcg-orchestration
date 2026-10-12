# Role usada SÓ pelos botões "Ligar/Desligar cluster EKS" (.github/workflows/eks-*.yml).
# O Terraform do cluster (infra/eks) cria/destrói EKS, EC2, ELB, IAM roles e OIDC provider,
# então a role precisa de AdministratorAccess. A porta de entrada é estreita: só um workflow
# do repo fcg-orchestration rodando no GitHub Environment `aws-eks` — que só aceita a branch
# main — consegue assumi-la (sub exato, sem curinga).
locals {
  github_oidc_provider_arn = "arn:aws:iam::915153720516:oidc-provider/token.actions.githubusercontent.com"
  eks_admin_subject        = "repo:FIAP-POS-TECH-TEAM-10/fcg-orchestration:environment:aws-eks"
}

resource "aws_iam_role" "eks_admin" {
  name                 = "GitHubActions-EKS-Admin"
  description          = "Botoes liga/desliga do cluster fcg-eks (fcg-orchestration, environment aws-eks)"
  max_session_duration = 7200

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.eks_admin_subject
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_admin" {
  role       = aws_iam_role.eks_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "eks_admin_role_arn" {
  value = aws_iam_role.eks_admin.arn
}
