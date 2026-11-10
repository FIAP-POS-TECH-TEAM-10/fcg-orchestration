# k8s — Kubernetes local (Kind / Docker Desktop)

Caminho antigo, só para cluster local. **Na AWS o deploy é outro:** [`k8s/eks`](eks/README.md).

Aqui ficam a infraestrutura comum (namespace, RabbitMQ, DynamoDB local); cada serviço tem os seus
manifests na pasta `k8s/` do próprio repositório.

1. Imagens locais: em cada repositório, o passo 0 do `k8s/README.md` gera a imagem com a tag que os manifests esperam.
2. Crie o Secret do RabbitMQ (o `rabbitmq-secret.yaml` daqui é só modelo) e aplique o resto:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl create secret generic rabbitmq-secret -n fcgames \
  --from-literal=username="$RABBITMQ_USER" --from-literal=password="$RABBITMQ_PASS"
kubectl apply -f k8s/rabbitmq-configmap.yaml -f k8s/rabbitmq-deployment.yaml -f k8s/rabbitmq-service.yaml \
  -f k8s/dynamodb-local-deployment.yaml -f k8s/dynamodb-local-service.yaml
```

3. Em cada serviço, siga o `k8s/README.md` dele (cria o Secret e aplica os manifests sem o modelo).

4. Acesse com `kubectl port-forward` (ex.: `kubectl port-forward -n fcgames svc/users-api 5001:80`).

Não use `k8s/deploy.sh` / `deploy.ps1`: eles aplicam as pastas inteiras, inclusive os modelos de
Secret com `REPLACE_ME`, por cima dos Secrets reais.
