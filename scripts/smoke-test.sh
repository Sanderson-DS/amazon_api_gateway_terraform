#!/usr/bin/env bash
set -euo pipefail

: "${PUBLIC_URL:?Defina PUBLIC_URL com terraform output -raw public_api_url}"
: "${ADMIN_URL:?Defina ADMIN_URL com terraform output -raw admin_api_url}"
: "${API_KEY:?Defina API_KEY com a chave administrativa do API Gateway}"

IMAGE_PATH="${1:-samples/images/1-Capa_Artigo-BI-DataScience.jpg}"
IMAGE_NAME="$(basename "$IMAGE_PATH")"

echo "1) Documentação pública"
curl -fsS "$PUBLIC_URL/fotos" >/dev/null

echo "2) Upload administrativo"
curl -fsS -X POST "$ADMIN_URL/bucket/$IMAGE_NAME" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: image/jpeg" \
  --data-binary "@$IMAGE_PATH"

echo
sleep 3

echo "3) Consulta por ID"
curl -fsS "$PUBLIC_URL/fotos/1"

echo

echo "4) Consulta por assunto"
curl -fsS "$PUBLIC_URL/fotos/assunto?nome=Capa_Artigo"

echo

echo "Smoke test concluído."
