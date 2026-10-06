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
