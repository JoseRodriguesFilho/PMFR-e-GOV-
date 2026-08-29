#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [ $# -lt 3 ]; then
  echo "Uso:"
  echo "  $0 CPF \"Nome Completo\" aluno"
  echo "  $0 CPF \"Nome Completo\" professor"
  echo "  $0 CPF \"Nome Completo\" admin"
  exit 1
fi

CPF="$1"
NAME="$2"
ROLE="$3"

case "$ROLE" in
  aluno|professor|admin) ;;
  *)
    echo "Role invalida: $ROLE"
    exit 1
    ;;
esac

set -a
source ./.env
set +a

ADMIN_TOKEN="${EGOV_ADMIN_TOKEN:-${LAB_ADMIN_TOKEN:-}}"
if [ -z "${ADMIN_TOKEN}" ]; then
  echo "Token administrativo nao encontrado no .env"
  exit 1
fi

curl -fsS -X POST "http://127.0.0.1:8089/admin/people" \
  -H "Content-Type: application/json" \
  -H "X-Admin-Token: ${ADMIN_TOKEN}" \
  -d "{\"cpf\":\"${CPF}\",\"name\":\"${NAME}\",\"role\":\"${ROLE}\",\"active\":true}"

echo
