# JWT gerado a cada criação do cluster — nunca aparece em código/YAML ("Zero Hardcoded
# Credentials"). Os deployments da parte 2 leem via secretKeyRef { name = "fcg-jwt",
# key = "jwt-key" } → env JWT__KEY. Recriar o cluster gera chave nova (tokens antigos expiram).
resource "random_password" "jwt_key" {
  length  = 64
  special = false
}

resource "kubernetes_secret_v1" "jwt" {
  metadata {
    name      = "fcg-jwt"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  data = {
    "jwt-key" = random_password.jwt_key.result
  }
}

# Senhas fixas escolhidas pelo time e guardadas em secrets do GitHub Actions (não em arquivo).
# O app lê fcg-admin como env ADMIN__PASSWORD; o Grafana lê fcg-grafana como
# GF_SECURITY_ADMIN_PASSWORD.
resource "kubernetes_secret_v1" "admin" {
  metadata {
    name      = "fcg-admin"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  data = {
    "admin-password" = var.admin_password
  }
}

resource "kubernetes_secret_v1" "grafana" {
  metadata {
    name      = "fcg-grafana"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  data = {
    "admin-password" = var.grafana_password
  }
}
