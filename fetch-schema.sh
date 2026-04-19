#!/usr/bin/env bash
#
# fetch-schema.sh — Extract the PostgreSQL schema from the ejabberd image
# into ./sql/pg.new.sql so that the postgres container's entrypoint will
# load it on first startup (via /docker-entrypoint-initdb.d/).
#
# Run this ONCE before the first `docker compose up -d`, or again if you
# upgrade the ejabberd image and want the newer schema for a fresh DB.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/sql"
IMAGE="${EJABBERD_IMAGE:-ghcr.io/processone/ejabberd:latest}"

mkdir -p "${SQL_DIR}"

echo "==> Pulling ${IMAGE} (if needed)..."
docker pull "${IMAGE}" >/dev/null

echo "==> Extracting pg.new.sql from ${IMAGE}..."
# The ejabberd image ships schema files under /opt/ejabberd/sql/.
# We pick pg.new.sql because the config sets `new_sql_schema: true`.
docker run --rm --entrypoint sh "${IMAGE}" -c 'cat /opt/ejabberd/sql/pg.new.sql' \
  > "${SQL_DIR}/pg.new.sql"

bytes=$(wc -c < "${SQL_DIR}/pg.new.sql")
if [[ "${bytes}" -lt 1000 ]]; then
  echo "ERROR: extracted schema is suspiciously small (${bytes} bytes)" >&2
  exit 1
fi

echo "==> Wrote ${SQL_DIR}/pg.new.sql (${bytes} bytes)"
echo
echo "The postgres container will auto-load this on the FIRST start (empty volume)."
echo "If you already started the stack once, you must reset the DB volume:"
echo "    docker compose down -v postgres   # or: docker volume rm <project>_postgres-data"
