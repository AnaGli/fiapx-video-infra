#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "Erro: arquivo .env não encontrado. Copie .env.example para .env e preencha os valores."
  exit 1
fi

get_env() {
  grep "^$1=" .env | head -n1 | cut -d '=' -f2- | tr -d '\r'
}

REQUIRED_VARS=(
  RABBITMQ_DEFAULT_USER
  RABBITMQ_DEFAULT_PASS
  LOCALSTACK_AUTH_TOKEN
  WORKER_DB_USER
  WORKER_DB_PASSWORD
  API_DB_USER
  API_DB_PASSWORD
  DD_API_KEY
)

for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "$(get_env "$var" || true)" ]; then
    echo "Erro: variável $var ausente ou vazia no .env"
    exit 1
  fi
done

apply_secret() {
  local name=$1 namespace=$2
  shift 2
  kubectl create secret generic "$name" -n "$namespace" "$@" \
    --dry-run=client -o yaml | kubectl apply -f -
}

echo "Aplicando namespaces..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/datadog-namespace.yaml
echo "Instalando Datadog Operator..."
helm repo add datadog https://helm.datadoghq.com >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install datadog-operator datadog/datadog-operator -n datadog
kubectl rollout status deployment/datadog-operator -n datadog --timeout=120s

echo "Aplicando Datadog Agent..."
kubectl apply -f k8s/datadog-agent.yaml

echo "Criando/atualizando secrets a partir do .env..."

apply_secret datadog-secret datadog \
  --from-literal=api-key="$(get_env DD_API_KEY)"

apply_secret rabbitmq-secrets video-infra \
  --from-literal=RABBITMQ_DEFAULT_USER="$(get_env RABBITMQ_DEFAULT_USER)" \
  --from-literal=RABBITMQ_DEFAULT_PASS="$(get_env RABBITMQ_DEFAULT_PASS)"

apply_secret localstack-secrets video-infra \
  --from-literal=LOCALSTACK_AUTH_TOKEN="$(get_env LOCALSTACK_AUTH_TOKEN)"

apply_secret video-worker-db-secrets video-infra \
  --from-literal=POSTGRES_USER="$(get_env WORKER_DB_USER)" \
  --from-literal=POSTGRES_PASSWORD="$(get_env WORKER_DB_PASSWORD)"

apply_secret video-api-db-secrets video-infra \
  --from-literal=POSTGRES_USER="$(get_env API_DB_USER)" \
  --from-literal=POSTGRES_PASSWORD="$(get_env API_DB_PASSWORD)"

echo "Aplicando RabbitMQ..."
kubectl apply -f k8s/rabbitmq.yaml

echo "Aplicando LocalStack..."
kubectl apply -f k8s/localstack.yaml

echo "Aplicando banco de dados do worker..."
kubectl apply -f k8s/video-worker-db.yaml

echo "Aplicando banco de dados da API..."
kubectl apply -f k8s/video-api-db.yaml

echo "Aguardando tudo ficar pronto..."
for deployment in rabbitmq localstack video-worker-db video-api-db; do
  kubectl rollout status deployment/"$deployment" -n video-infra --timeout=90s
done

echo ""
echo "Infraestrutura pronta. Endpoints internos para os microsserviços:"
echo "  RabbitMQ:      rabbitmq.video-infra.svc.cluster.local:5672"
echo "  RabbitMQ UI:   kubectl port-forward -n video-infra svc/rabbitmq 15672:15672"
echo "  LocalStack:    http://localstack.video-infra.svc.cluster.local:4566"
echo "  DB do worker:  video-worker-db.video-infra.svc.cluster.local:5432"
echo "  DB da API:     video-api-db.video-infra.svc.cluster.local:5432"