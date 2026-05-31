#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"

if [ -f "${ROOT_DIR}/.env" ]; then
  set +u
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/.env"
  set +a
  set -u
  # shellcheck source=scripts/lib/env-aliases.sh
  source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
fi

if [ -z "${AWS_ACCOUNT_ID:-}" ] && command -v aws >/dev/null 2>&1; then
  export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
fi

# shellcheck source=scripts/resolve-ecr-registry.sh
source "${ROOT_DIR}/scripts/resolve-ecr-registry.sh"

bash "${ROOT_DIR}/scripts/validate-production-config.sh"

bash "${ROOT_DIR}/scripts/render-k8s-manifests.sh" "${ROOT_DIR}/.rendered-k8s"

RENDERED="${ROOT_DIR}/.rendered-k8s/infrastructure/kubernetes"

kubectl apply -f "${RENDERED}/namespaces/"
kubectl apply -f "${RENDERED}/serviceaccounts/"
kubectl apply -f "${RENDERED}/secrets/"

bash "${ROOT_DIR}/scripts/sync-rabbitmq-credentials.sh"
bash "${ROOT_DIR}/scripts/sync-postgres-password.sh"
if [ "${SKIP_MONGO_PASSWORD_SYNC:-false}" != "true" ]; then
  bash "${ROOT_DIR}/scripts/sync-mongo-password.sh"
else
  echo "Skipping MongoDB password sync (SKIP_MONGO_PASSWORD_SYNC=true)."
fi

if [ -d "${RENDERED}/configmaps" ]; then
  kubectl apply -f "${RENDERED}/configmaps/"
fi

if [ -d "${RENDERED}/postgres" ]; then
  for manifest in "${RENDERED}"/postgres/*.yaml; do
    [ -f "${manifest}" ] || continue
    case "${manifest}" in
      *migration-job.yaml) continue ;;
    esac
    kubectl apply -f "${manifest}"
  done
fi

if [ "${RUN_POSTGRES_MIGRATIONS:-true}" = "true" ]; then
  echo "Running Postgres migrations..."
  if [ -f "${RENDERED}/postgres/migration-job.yaml" ]; then
    kubectl delete job postgres-migrations -n "${K8S_NAMESPACE}" --ignore-not-found --wait=true
    kubectl apply -f "${RENDERED}/postgres/migration-job.yaml"
    kubectl wait --for=condition=complete job/postgres-migrations -n "${K8S_NAMESPACE}" --timeout=90s
  else
    bash "${ROOT_DIR}/scripts/run-postgres-migrations.sh" || {
      echo "Postgres migration script failed; ensure POSTGRES_* env vars are reachable."
      exit 1
    }
  fi
fi

if [ -f "${RENDERED}/mongodb/index-job.yaml" ]; then
  kubectl delete job mongodb-index-setup -n "${K8S_NAMESPACE}" --ignore-not-found
  kubectl apply -f "${RENDERED}/mongodb/index-job.yaml"
  kubectl wait --for=condition=complete job/mongodb-index-setup -n "${K8S_NAMESPACE}" --timeout=90s
fi

if [ -f "${RENDERED}/cleanup/s3-orphan-cleanup-cronjob.yaml" ]; then
  kubectl apply -f "${RENDERED}/cleanup/s3-orphan-cleanup-cronjob.yaml"
fi

# Deploy API workloads first, then dedicated queue workers.
for dir in gateway auth converter notification redis frontend; do
  for kind in deployment service ingress hpa; do
    manifest="${RENDERED}/${dir}/${kind}.yaml"
    if [ -f "${manifest}" ]; then
      kubectl apply -f "${manifest}"
    fi
  done
done

for dir in gateway converter notification; do
  manifest="${RENDERED}/${dir}/worker-deployment.yaml"
  if [ -f "${manifest}" ]; then
    kubectl apply -f "${manifest}"
  fi
  cleanup_manifest="${RENDERED}/${dir}/cleanup-cronjob.yaml"
  if [ -f "${cleanup_manifest}" ]; then
    kubectl apply -f "${cleanup_manifest}"
  fi
done

if [ "${APPLY_NETWORK_POLICIES:-true}" = "true" ]; then
  bash "${ROOT_DIR}/scripts/deploy-network-policies.sh"
fi

if [ "${INSTALL_KEDA:-true}" = "true" ]; then
  bash "${ROOT_DIR}/scripts/install-keda.sh"
fi

scaling_dir="${RENDERED}/autoscaling"
scaledobject_manifest="${scaling_dir}/converter-scaledobject.yaml"
if [ -f "${scaledobject_manifest}" ]; then
  if kubectl get crd scaledobjects.keda.sh >/dev/null 2>&1; then
    echo "Applying KEDA ScaledObject..."
    kubectl apply -f "${scaledobject_manifest}"
    if kubectl get scaledobject "${CONVERTER_SCALEDOBJECT_NAME:-converter-worker-scaler}" \
      -n "${K8S_NAMESPACE}" >/dev/null 2>&1; then
      kubectl wait --for=condition=Ready \
        "scaledobject/${CONVERTER_SCALEDOBJECT_NAME:-converter-worker-scaler}" \
        -n "${K8S_NAMESPACE}" \
        --timeout=90s
    fi
  else
    echo "ERROR: KEDA CRD missing after install step." >&2
    exit 1
  fi
fi

if [ "${DEPLOY_MONITORING_STACK:-true}" = "true" ] && [ -n "${GRAFANA_ADMIN_PASSWORD:-}" ] && [ "${GRAFANA_ADMIN_PASSWORD}" != "changeme" ]; then
  bash "${ROOT_DIR}/scripts/deploy-monitoring.sh"
fi

echo "Microservices deployed successfully."
