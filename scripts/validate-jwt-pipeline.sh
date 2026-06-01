#!/bin/bash
# Local end-to-end validation for JWT secret render + service config import.
# Run before deploy to catch PEM/auth issues without a cluster round-trip.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

PRIV_PEM="$(openssl genrsa 2048 2>/dev/null)"
PUB_PEM="$(printf '%s' "${PRIV_PEM}" | openssl pkey -pubout 2>/dev/null)"
ESCAPED_PRIV="$(printf '%s' "${PRIV_PEM}" | sed ':a;N;$!ba;s/\n/\\n/g')"

if [ -z "${JWT_PRIVATE_KEY:-}" ]; then
  export JWT_PRIVATE_KEY="${ESCAPED_PRIV}"
fi
export K8S_NAMESPACE="${K8S_NAMESPACE:-video-processing}"
export JWT_SECRET="${JWT_SECRET:-test-secret}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-p}"
export POSTGRES_USER="${POSTGRES_USER:-u}"
export POSTGRES_HOST="${POSTGRES_HOST:-h}"
export POSTGRES_DB="${POSTGRES_DB:-d}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export MONGO_PASSWORD="${MONGO_PASSWORD:-m}"
export MONGO_USERNAME="${MONGO_USERNAME:-mu}"
export RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-r}"
export RABBITMQ_USERNAME="${RABBITMQ_USERNAME:-ru}"
export SMTP_USERNAME="${SMTP_USERNAME:-su}"
export SMTP_PASSWORD="${SMTP_PASSWORD:-sp}"
export REDIS_PASSWORD="${REDIS_PASSWORD:-rp}"
export FRONTEND_URL="${FRONTEND_URL:-https://example.com}"
export APP_ENV="${APP_ENV:-production}"

# shellcheck source=scripts/lib/env-aliases.sh
source "${ROOT_DIR}/scripts/lib/env-aliases.sh"
bash "${ROOT_DIR}/scripts/render-k8s-secrets.sh" "${TMP_DIR}/rendered"
export VALIDATE_RENDER_DIR="${TMP_DIR}/rendered"
export VALIDATE_REPO_DIR="${ROOT_DIR}"

python3 <<'PY'
import base64, importlib, os, sys, yaml

import jwt

repo = os.environ["VALIDATE_REPO_DIR"]
render = os.environ["VALIDATE_RENDER_DIR"]
secret_path = f"{render}/infrastructure/kubernetes/secrets/auth-secret.yaml"
data = yaml.safe_load(open(secret_path))["data"]

def k8s_env(key: str) -> str:
    return base64.b64decode(data[key]).decode("utf-8")

for key in ("JWT_PRIVATE_KEY", "JWT_PUBLIC_KEY"):
    if key not in data:
        raise SystemExit(f"missing secret key: {key}")

os.environ["JWT_PRIVATE_KEY"] = k8s_env("JWT_PRIVATE_KEY")
os.environ["JWT_PUBLIC_KEY"] = k8s_env("JWT_PUBLIC_KEY")
os.environ["JWT_ISSUER"] = k8s_env("JWT_ISSUER")
os.environ["JWT_AUDIENCE"] = k8s_env("JWT_AUDIENCE")
os.environ["APP_ENV"] = "production"
os.environ["FRONTEND_URL"] = "https://example.com"
os.environ["POSTGRES_PASSWORD"] = "p"
os.environ["POSTGRES_USER"] = "u"
os.environ["POSTGRES_HOST"] = "h"
os.environ["POSTGRES_DB"] = "d"

sys.path[:0] = [
    f"{repo}/services/auth",
    repo,
    f"{repo}/services/gateway",
]

from shared.security.pem_loader import load_pem, verify_rsa_key_pair

priv = load_pem("JWT_PRIVATE_KEY", "/run/secrets/jwt-private.pem")
pub = load_pem("JWT_PUBLIC_KEY", "/run/secrets/jwt-public.pem")
if not verify_rsa_key_pair(priv, pub):
    raise SystemExit("JWT key pair failed signing check after secret render")

import app.config as auth_config  # noqa: E402

importlib.reload(auth_config)
if not auth_config.JWT_PRIVATE_KEY or not auth_config.JWT_PUBLIC_KEY:
    raise SystemExit("auth config did not load JWT keys")

os.chdir(f"{repo}/services/gateway")
import app.config as gateway_config  # noqa: E402

importlib.reload(gateway_config)
if not gateway_config.JWT_PUBLIC_KEY:
    raise SystemExit("gateway config missing JWT_PUBLIC_KEY")

token = jwt.encode({"healthcheck": "1"}, priv, algorithm="RS256")
jwt.decode(token, pub, algorithms=["RS256"])
print("JWT pipeline OK")
PY

echo "validate-jwt-pipeline: OK"
