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
