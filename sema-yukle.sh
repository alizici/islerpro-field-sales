#!/usr/bin/env bash
# Şemayı Supabase'e yükler. Gizli değerleri .env.local'dan okur — sohbete girmez.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"

[ -f .env ] || { echo "✗ .env yok"; exit 1; }
[ -f .env.local ] || {
  echo "✗ .env.local yok. Önce:  cp .env.local.example .env.local  ve doldurun."
  exit 1; }

set -a; source .env; source .env.local; set +a
REF="${SUPABASE_URL#https://}"; REF="${REF%%.supabase.co}"

: "${SUPABASE_ACCESS_TOKEN:?.env.local içinde SUPABASE_ACCESS_TOKEN boş}"
: "${SUPABASE_DB_PASSWORD:?.env.local içinde SUPABASE_DB_PASSWORD boş}"

echo "→ proje: $REF"
supabase link --project-ref "$REF" --password "$SUPABASE_DB_PASSWORD"
echo "→ migration'lar uygulanıyor…"
supabase db push --password "$SUPABASE_DB_PASSWORD"
echo "✓ tamamlandı"
