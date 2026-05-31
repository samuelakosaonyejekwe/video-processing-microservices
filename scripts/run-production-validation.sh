#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
# shellcheck source=scripts/setup-production-test-endpoints.sh
source "${ROOT_DIR}/scripts/setup-production-test-endpoints.sh"

export DEPLOY_ROLLOUT_TIMEOUT="${DEPLOY_ROLLOUT_TIMEOUT:-120s}"
export WORKER_ROLLOUT_TIMEOUT="${WORKER_ROLLOUT_TIMEOUT:-120s}"

trap cleanup_production_test_endpoints EXIT

echo "=== Kubernetes cluster validation ==="
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A

echo "=== Core deployment rollouts ==="
bash "${ROOT_DIR}/scripts/verify-deployment.sh"
bash "${ROOT_DIR}/scripts/validate-queue-workers.sh"

echo "=== Metrics server and HPA validation ==="
bash "${ROOT_DIR}/scripts/validate-hpa.sh"
bash "${ROOT_DIR}/scripts/validate-keda.sh"

echo "=== IAM deploy permission check ==="
bash "${ROOT_DIR}/scripts/verify-github-actions-iam.sh" || true

echo "=== RabbitMQ validation ==="
messaging_ns="${MESSAGING_NAMESPACE:-messaging}"
kubectl get pods -n "${messaging_ns}" 2>/dev/null || kubectl get pods -A | grep -i rabbit || true
kubectl get svc -n "${messaging_ns}" 2>/dev/null || true

echo "=== Configure production test endpoints ==="
setup_production_test_endpoints

echo "=== Production E2E tests ==="
export INTEGRATION_TESTS=true
export PRODUCTION_VALIDATION=true
if [ ! -d "${ROOT_DIR}/.venv" ]; then
  python3 -m venv "${ROOT_DIR}/.venv"
fi
# shellcheck disable=SC1091
source "${ROOT_DIR}/.venv/bin/activate"
pip install -q pytest httpx requests
for service in gateway auth converter notification; do
  pip install -q -r "${ROOT_DIR}/services/${service}/requirements.txt"
done
python -m pytest "${ROOT_DIR}/tests/integration" "${ROOT_DIR}/tests/e2e" -v --tb=short

echo "=== RabbitMQ queue health check ==="
chmod +x "${ROOT_DIR}/scripts/check-rabbitmq-video-queues.sh"
bash "${ROOT_DIR}/scripts/check-rabbitmq-video-queues.sh" k8s

echo "=== Production validation completed ==="
