#!/bin/bash
set -e

cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "Erro: arquivo .env não encontrado. Copie .env.example para .env e preencha os valores."
  exit 1
fi

get_env() {
  grep "^$1=" .env | cut -d '=' -f2-
}

echo "Aplicando namespace..."
kubectl apply -f k8s/namespace.yaml

echo "Criando/atualizando secrets a partir do .env..."

kubectl delete secret rabbitmq-secrets -n video-infra --ignore-not-found
kubectl create secret generic rabbitmq-secrets -n video-infra \
  --from-literal=RABBITMQ_DEFAULT_USER="$(get_env RABBITMQ_DEFAULT_USER)" \
  --from-literal=RABBITMQ_DEFAULT_PASS="$(get_env RABBITMQ_DEFAULT_PASS)"

kubectl delete secret localstack-secrets -n video-infra --ignore-not-found
kubectl create secret generic localstack-secrets -n video-infra \
  --from-literal=LOCALSTACK_AUTH_TOKEN="$(get_env LOCALSTACK_AUTH_TOKEN)"

kubectl delete secret video-worker-db-secrets -n video-infra --ignore-not-found
kubectl create secret generic video-worker-db-secrets -n video-infra \
  --from-literal=POSTGRES_USER="$(get_env WORKER_DB_USER)" \
  --from-literal=POSTGRES_PASSWORD="$(get_env WORKER_DB_PASSWORD)"

kubectl delete secret video-api-db-secrets -n video-infra --ignore-not-found
kubectl create secret generic video-api-db-secrets -n video-infra \
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
kubectl wait --for=condition=ready pod -l app=rabbitmq -n video-infra --timeout=90s
kubectl wait --for=condition=ready pod -l app=localstack -n video-infra --timeout=90s
kubectl wait --for=condition=ready pod -l app=video-worker-db -n video-infra --timeout=90s
kubectl wait --for=condition=ready pod -l app=video-api-db -n video-infra --timeout=90s

echo ""
echo "Infraestrutura pronta. Endpoints internos para os microsserviços:"
echo "  RabbitMQ:      rabbitmq.video-infra.svc.cluster.local:5672"
echo "  RabbitMQ UI:   kubectl port-forward -n video-infra svc/rabbitmq 15672:15672"
echo "  LocalStack:    http://localstack.video-infra.svc.cluster.local:4566"
echo "  DB do worker:  video-worker-db.video-infra.svc.cluster.local:5432"
echo "  DB da API:     video-api-db.video-infra.svc.cluster.local:5432"
