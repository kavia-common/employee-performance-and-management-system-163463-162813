#!/usr/bin/env bash
# Apply all SQL files in schema/ folder to the configured MySQL instance using env vars.
# Usage:
#   source ./db_visualizer/mysql.env
#   ./scripts/apply_migrations.sh
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_DIR="${BASE_DIR}/schema"

: "${MYSQL_USER:?MYSQL_USER must be set (e.g., source db_visualizer/mysql.env)}"
: "${MYSQL_PASSWORD:?MYSQL_PASSWORD must be set}"
: "${MYSQL_DB:?MYSQL_DB must be set}"
: "${MYSQL_PORT:?MYSQL_PORT must be set}"

HOST="${MYSQL_HOST:-127.0.0.1}"

echo "Applying migrations to mysql://${HOST}:${MYSQL_PORT}/${MYSQL_DB} as ${MYSQL_USER}"
for file in $(ls "${SCHEMA_DIR}"/*.sql | sort); do
  echo ">> Applying $(basename "$file")"
  mysql -h "${HOST}" -P "${MYSQL_PORT}" -u "${MYSQL_USER}" "-p${MYSQL_PASSWORD}" "${MYSQL_DB}" < "$file"
done
echo "All migrations applied."
