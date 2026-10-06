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

  # O addon metrics-server escuta em 10251 (não 10250) e o SG de node do módulo só libera
  # 10250 vindo do control plane — sem isso o APIService metrics.k8s.io dá timeout
  # (`kubectl top` → "Metrics API not available", e o HPA não funciona).
  node_security_group_additional_rules = {
    ingress_cluster_metrics_server = {
      description                   = "Control plane para metrics-server"
      protocol                      = "tcp"
      from_port                     = 10251
      to_port                       = 10251
      type                          = "ingress"
      source_cluster_security_group = true
    }
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
