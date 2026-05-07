#!/usr/bin/env bash
set -euo pipefail

# Day 2 Demo: Apply schema change (migration 004 — add is_favorited) with zero downtime.
# Usage: ./scripts/demo-schema-change.sh <namespace> [blue|green]
# Example: ./scripts/demo-schema-change.sh samosachaat-prod blue

NAMESPACE="${1:?Usage: demo-schema-change.sh <namespace> [blue|green]}"
SLOT="${2:-}"
SUFFIX=""
if [[ -n "$SLOT" ]]; then
  if [[ ! "$SLOT" =~ ^(blue|green)$ ]]; then
    echo "Unsupported slot: $SLOT" >&2
    exit 2
  fi
  SUFFIX="-$SLOT"
fi

RELEASE="samosachaat${SUFFIX}"
CHAT_API_DEPLOYMENT="chat-api${SUFFIX}"

echo "=== samosaChaat Day 2: Schema Change Demo ==="

echo ""
echo "Step 1: Current migration state"
kubectl exec -n "$NAMESPACE" "deploy/$CHAT_API_DEPLOYMENT" -- alembic -c db/alembic.ini current 2>/dev/null || \
  echo "(Could not connect — ensure chat-api pod is running)"

echo ""
echo "Step 2: Show the migration file"
echo "File: db/migrations/versions/004_add_favorited.py"
echo "Operation: ALTER TABLE conversations ADD COLUMN is_favorited BOOLEAN DEFAULT false NOT NULL"
echo ""
echo "Key points:"
echo "  - ADD COLUMN with DEFAULT is non-blocking in PostgreSQL 11+"
echo "  - No table lock, no downtime, existing rows get default value instantly"
echo "  - Old pods (without the code change) simply ignore the new column"
echo "  - New pods (with updated SQLAlchemy model) can use it immediately"

echo "Step 3: Apply migration via Helm upgrade"
echo "The db-migrate-job.yaml Helm hook runs 'alembic upgrade head' before new pods start."
echo ""
echo "Running: helm upgrade $RELEASE helm/samosachaat -n $NAMESPACE --reuse-values"
helm upgrade "$RELEASE" helm/samosachaat -n "$NAMESPACE" --reuse-values

echo ""
echo "Step 4: Verify migration applied"
kubectl exec -n "$NAMESPACE" "deploy/$CHAT_API_DEPLOYMENT" -- alembic -c db/alembic.ini current

echo ""
echo "Step 5: Verify column exists in database"
kubectl exec -n "$NAMESPACE" "deploy/$CHAT_API_DEPLOYMENT" -- python -c "
import asyncio
import os
import asyncpg

url = os.environ.get('DATABASE_URL', '').replace('postgresql+asyncpg://', 'postgresql://')
if not url:
    print('DATABASE_URL not set')
    exit(1)

async def main():
    conn = await asyncpg.connect(url)
    try:
        rows = await conn.fetch(\"\"\"
            SELECT column_name
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'conversations'
            ORDER BY ordinal_position
        \"\"\")
    finally:
        await conn.close()
    cols = [row['column_name'] for row in rows]
    print(f'Columns: {cols}')
    assert 'is_favorited' in cols, 'FAIL: is_favorited not found!'
    print('SUCCESS: is_favorited column present and migration is complete.')

asyncio.run(main())
"
