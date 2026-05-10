#!/usr/bin/env bash
# Конструктор Строений — деплой Flutter web в Yandex Object Storage
# и сброс CDN-кеша. Использует уже настроенный AWS CLI-профиль `yc`
# (endpoint https://storage.yandexcloud.net).
#
# Переменные окружения:
#   YC_S3_BUCKET        — S3-бакет (по умолчанию konstruktor-stroenii).
#   YC_OAUTH_TOKEN      — OAuth-токен Yandex Cloud для CDN purge.
#   YC_CDN_RESOURCE_ID  — id ресурса CDN.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

BUCKET="${YC_S3_BUCKET:-konstruktor-stroenii}"

AUTH_API="${AUTH_API_BASE_URL:-https://89-169-141-69.sslip.io}"

echo "[1/3] flutter build web --release (AUTH_API_BASE_URL=$AUTH_API)"
flutter build web --release --dart-define=AUTH_API_BASE_URL="$AUTH_API"

echo "[2/3] aws s3 sync build/web → s3://$BUCKET/"
aws --profile yc --endpoint-url=https://storage.yandexcloud.net \
    s3 sync build/web "s3://$BUCKET/" \
    --delete \
    --exclude ".DS_Store"

if [[ -n "${YC_OAUTH_TOKEN:-}" && -n "${YC_CDN_RESOURCE_ID:-}" ]]; then
  echo "[3/3] CDN purge $YC_CDN_RESOURCE_ID"
  # Yandex Cloud CDN API ожидает IAM-токен. Сначала меняем
  # OAuth-токен на IAM, затем выполняем purge.
  IAM_TOKEN="$(curl -fsSL -X POST \
    -H "Content-Type: application/json" \
    "https://iam.api.cloud.yandex.net/iam/v1/tokens" \
    -d "{\"yandexPassportOauthToken\":\"$YC_OAUTH_TOKEN\"}" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin).get("iamToken",""))')"
  if [[ -z "$IAM_TOKEN" ]]; then
    echo "Не удалось получить IAM-токен — пропускаю purge" >&2
  else
    curl -fsSL -X POST \
      -H "Authorization: Bearer $IAM_TOKEN" \
      -H "Content-Type: application/json" \
      "https://cdn.api.cloud.yandex.net/cdn/v1/cache/$YC_CDN_RESOURCE_ID:purge" \
      -d '{"paths": ["/*"]}'
    echo
  fi
else
  echo "[3/3] пропускаю CDN purge — нет YC_OAUTH_TOKEN/YC_CDN_RESOURCE_ID"
fi

echo "Готово. Проверьте https://konstruktor-stroenii.ru/"
