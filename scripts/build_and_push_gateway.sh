#!/usr/bin/env bash
# =============================================================================
# Build & Push de la imagen Docker del Claude Apps Gateway hacia Amazon ECR
# =============================================================================
# Este script es invocado automaticamente por Terraform (null_resource en el
# modulo 05-gateway-ecs) durante `terraform apply`, y tambien puede ejecutarse
# manualmente desde la raiz del repositorio.
#
# Variables de entorno soportadas:
#   ECR_REPOSITORY_URL  (Requerido) URL del repositorio ECR en la Cuenta B
#   WORKLOAD_ACCOUNT_ID (Requerido) ID de 12 digitos de la Cuenta B (Workload)
#   AWS_REGION          (Opcional)  Region de AWS (por defecto: eu-west-1)
#   ASSUME_ROLE_ARN     (Opcional)  ARN del rol IAM en la Cuenta B a asumir
#   IMAGE_TAG           (Opcional)  Tag de la imagen Docker (por defecto: latest)
#   CLAUDE_VERSION      (Opcional)  Version del binario Claude (por defecto: latest)
#   DOCKER_CONTEXT_DIR  (Opcional)  Ruta al directorio docker/ (por defecto: ./docker)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

AWS_REGION="${AWS_REGION:-eu-west-1}"
ECR_REPOSITORY_URL="${ECR_REPOSITORY_URL:-${1:-}}"
WORKLOAD_ACCOUNT_ID="${WORKLOAD_ACCOUNT_ID:-${2:-}}"
ASSUME_ROLE_ARN="${ASSUME_ROLE_ARN:-${3:-}}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
CLAUDE_VERSION="${CLAUDE_VERSION:-latest}"
DOCKER_CONTEXT_DIR="${DOCKER_CONTEXT_DIR:-${REPO_ROOT}/docker}"

if [[ -z "${ECR_REPOSITORY_URL}" || -z "${WORKLOAD_ACCOUNT_ID}" ]]; then
  echo "Uso: ECR_REPOSITORY_URL=<url> WORKLOAD_ACCOUNT_ID=<account_id> [ASSUME_ROLE_ARN=<role_arn>] $0" >&2
  exit 1
fi

echo "==> [1/5] Verificando prerrequisitos locales (docker y aws CLI)..."
for cmd in docker aws; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: El comando '$cmd' es obligatorio pero no esta instalado en el PATH." >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: El demonio de Docker no esta en ejecucion o el usuario actual no tiene permisos." >&2
  exit 1
fi

echo "==> [2/5] Verificando identidad de AWS y acceso a la Cuenta B (${WORKLOAD_ACCOUNT_ID})..."
CURRENT_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

if [[ "${CURRENT_ACCOUNT_ID}" != "${WORKLOAD_ACCOUNT_ID}" && -n "${ASSUME_ROLE_ARN}" ]]; then
  echo "    Asumiendo rol cross-account '${ASSUME_ROLE_ARN}' hacia la Cuenta B..."
  read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN < <(
    aws sts assume-role \
      --role-arn "${ASSUME_ROLE_ARN}" \
      --role-session-name "ECRBuildPushGateway" \
      --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
      --output text
  )
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
fi

ECR_REGISTRY="${ECR_REPOSITORY_URL%/*}"
FULL_IMAGE_URI="${ECR_REPOSITORY_URL}:${IMAGE_TAG}"

echo "==> [3/5] Autenticando Docker contra Amazon ECR (${ECR_REGISTRY}) en ${AWS_REGION}..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "==> [4/5] Construyendo imagen Docker linux/amd64 para Claude Apps Gateway (version=${CLAUDE_VERSION})..."
docker build \
  --platform=linux/amd64 \
  --build-arg CLAUDE_VERSION="${CLAUDE_VERSION}" \
  -t "${FULL_IMAGE_URI}" \
  "${DOCKER_CONTEXT_DIR}"

echo "==> [5/5] Subiendo imagen ${FULL_IMAGE_URI} a Amazon ECR en la Cuenta B..."
docker push "${FULL_IMAGE_URI}"

echo "==> Imagen publicada exitosamente en ECR: ${FULL_IMAGE_URI}"
