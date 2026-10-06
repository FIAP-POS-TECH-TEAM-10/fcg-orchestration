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
  # Fixado: a policy IAM do módulo eks-pod-identity cobre todas as ações do iam_policy.json da v3.6.0.
  version   = "3.6.0"
  namespace = "kube-system"
  wait      = true

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
