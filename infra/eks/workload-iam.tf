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
