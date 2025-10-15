#!/usr/bin/env bash
# ==============================================================================
# medical-mcp-toolkit — DB Schema Inspector (Dockerized Postgres)
#
# Prints: server info, extensions, schemas, tables, views, enums, and for each
# expected table: columns, indexes, constraints, storage size, and row estimates.
#
# Defaults align with Dockerfile.db / Makefile in this repo.
#
# Usage:
#   scripts/db_schema_check.sh [--container NAME] [--user USER] [--db DB]
#                              [--schema SCHEMA] [--tables "t1 t2 ..."]
#                              [--exact] [--quiet]
#
# Examples:
#   scripts/db_schema_check.sh
#   scripts/db_schema_check.sh --schema public --tables "patients vitals"
#   DB_CONTAINER_NAME=medical-db-container scripts/db_schema_check.sh --exact
#
# Exit codes:
#   0 success, non-zero on error.
# ==============================================================================

set -Eeuo pipefail

# ----- Defaults (can be overridden by env or CLI) -----------------------------
DB_CONTAINER_NAME="${DB_CONTAINER_NAME:-medical-db-container}"
POSTGRES_USER="${POSTGRES_USER:-mcp_user}"
POSTGRES_DB="${POSTGRES_DB:-medical_db}"
DB_SCHEMA="${DB_SCHEMA:-public}"

# Expected tables (space-separated; can override with --tables)
EXPECTED_TABLES_DEFAULT="patients vitals conditions allergies medications drugs drug_interactions appointments tool_audit"

# Flags
EXACT_COUNTS=0
QUIET=0

# ----- Helpers ----------------------------------------------------------------
die() { echo "❌ $*" >&2; exit 1; }
say() { [[ "$QUIET" -eq 1 ]] || echo -e "$*"; }
hr()  { [[ "$QUIET" -eq 1 ]] || printf '%s\n' "----------------------------------------------------------------"; }

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -c, --container NAME   Docker container name (default: ${DB_CONTAINER_NAME})
  -U, --user USER        Postgres user          (default: ${POSTGRES_USER})
  -d, --db DBNAME        Postgres database      (default: ${POSTGRES_DB})
  -s, --schema SCHEMA    Schema to inspect      (default: ${DB_SCHEMA})
  -t, --tables "T1 T2"   Space-separated list of tables to detail
                         (default: ${EXPECTED_TABLES_DEFAULT})
  -x, --exact            Use exact row counts (slower on big tables)
  -q, --quiet            Less verbose output
  -h, --help             Show this help

Environment overrides also supported:
  DB_CONTAINER_NAME, POSTGRES_USER, POSTGRES_DB, DB_SCHEMA
EOF
}

# ----- Parse CLI --------------------------------------------------------------
EXPECTED_TABLES="${EXPECTED_TABLES_DEFAULT}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--container) DB_CONTAINER_NAME="$2"; shift 2 ;;
    -U|--user)      POSTGRES_USER="$2"; shift 2 ;;
    -d|--db)        POSTGRES_DB="$2"; shift 2 ;;
    -s|--schema)    DB_SCHEMA="$2"; shift 2 ;;
    -t|--tables)    EXPECTED_TABLES="$2"; shift 2 ;;
    -x|--exact)     EXACT_COUNTS=1; shift ;;
    -q|--quiet)     QUIET=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)";;
  esac
done

# ----- Pre-flight checks ------------------------------------------------------
command -v docker >/dev/null 2>&1 || die "Docker is not installed or not in PATH."

if ! docker ps --format '{{.Names}}' | grep -qx "${DB_CONTAINER_NAME}"; then
  die "Container '${DB_CONTAINER_NAME}' is not running. Start it with: make db-up"
fi

# Verify psql is available inside the container
if ! docker exec -i "${DB_CONTAINER_NAME}" bash -lc 'command -v psql >/dev/null 2>&1'; then
  die "psql is not available inside container '${DB_CONTAINER_NAME}'. Is this a Postgres image?"
fi

PSQL=(docker exec -i "${DB_CONTAINER_NAME}" psql -X -q -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -P pager=off)

run_sql() {
  local sql="$1"
  "${PSQL[@]}" -c "$sql"
}

title() { say ""; say "📌 $*"; hr; }

# ----- Introspection ----------------------------------------------------------
say "🔌 Connecting to container: ${DB_CONTAINER_NAME}"
hr
run_sql '\conninfo' || die "Failed to connect with psql."

title "🧭 Server / Database Info"
run_sql "SHOW server_version;"
run_sql "SELECT current_database() AS db, current_user AS user, current_setting('TimeZone') AS timezone;"

title "🧩 Installed Extensions"
run_sql "SELECT extname AS extension, extversion AS version
         FROM pg_extension
         ORDER BY extname;"

title "📦 Schemas (user-visible)"
run_sql "SELECT nspname AS schema, pg_catalog.pg_get_userbyid(nspowner) AS owner
         FROM pg_namespace
         WHERE nspname NOT IN ('pg_catalog','information_schema')
         ORDER BY nspname;"

title "📑 Tables in schema '${DB_SCHEMA}'"
run_sql "SELECT table_name
         FROM information_schema.tables
         WHERE table_schema='${DB_SCHEMA}' AND table_type='BASE TABLE'
         ORDER BY table_name;"

title "🔭 Views in schema '${DB_SCHEMA}'"
run_sql "SELECT table_name AS view_name
         FROM information_schema.views
         WHERE table_schema='${DB_SCHEMA}'
         ORDER BY table_name;"

title "🧱 Materialized Views in schema '${DB_SCHEMA}'"
run_sql "SELECT matviewname AS matview_name
         FROM pg_matviews
         WHERE schemaname='${DB_SCHEMA}'
         ORDER BY matviewname;"

title "🎨 ENUM types in '${DB_SCHEMA}'"
run_sql "SELECT t.typname AS enum_name,
                string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder) AS values
         FROM pg_type t
         JOIN pg_enum e ON t.oid = e.enumtypid
         JOIN pg_namespace n ON n.oid = t.typnamespace
         WHERE n.nspname = '${DB_SCHEMA}'
         GROUP BY t.typname
         ORDER BY t.typname;"

title "🧠 Views definitions (first 2, if present)"
run_sql "SELECT viewname, pg_get_viewdef((quote_ident(schemaname)||'.'||quote_ident(viewname))::regclass, true) AS definition
         FROM pg_views
         WHERE schemaname='${DB_SCHEMA}'
         AND viewname IN ('v_latest_vitals','v_patient_profile')
         ORDER BY viewname;"

# ----- Per-table deep dive ----------------------------------------------------
title "📋 Column details, indexes, constraints, sizes & row counts"
IFS=' ' read -r -a TABLES <<< "${EXPECTED_TABLES}"
for tbl in "${TABLES[@]}"; do
  say ""
  say "▶ ${DB_SCHEMA}.${tbl}"
  hr

  # Columns
  run_sql "
    SELECT
      c.ordinal_position AS pos,
      c.column_name      AS name,
      COALESCE(c.data_type, c.udt_name) AS data_type,
      c.is_nullable      AS nullable,
      c.column_default   AS default
    FROM information_schema.columns c
    WHERE c.table_schema='${DB_SCHEMA}' AND c.table_name='${tbl}'
    ORDER BY c.ordinal_position;
  " || true

  # Indexes
  say "• Indexes"
  run_sql "
    SELECT indexname AS name, indexdef AS definition
    FROM pg_indexes
    WHERE schemaname='${DB_SCHEMA}' AND tablename='${tbl}'
    ORDER BY indexname;
  " || true

  # Constraints
  say "• Constraints"
  run_sql "
    SELECT con.conname AS name,
           CASE con.contype
             WHEN 'p' THEN 'PRIMARY KEY'
             WHEN 'u' THEN 'UNIQUE'
             WHEN 'f' THEN 'FOREIGN KEY'
             WHEN 'c' THEN 'CHECK'
             WHEN 'x' THEN 'EXCLUDE'
             ELSE con.contype::text
           END AS type,
           pg_get_constraintdef(con.oid, true) AS definition
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE nsp.nspname='${DB_SCHEMA}' AND rel.relname='${tbl}'
    ORDER BY con.conname;
  " || true

  # Size + row count
  if [[ "${EXACT_COUNTS}" -eq 1 ]]; then
    say "• Size & rows (exact)"
    run_sql "
      SELECT
        '${tbl}' AS table_name,
        pg_size_pretty(pg_total_relation_size('${DB_SCHEMA}.${tbl}')) AS total_size,
        (SELECT COUNT(*)::bigint FROM ${DB_SCHEMA}.${tbl}) AS exact_rows;
    " || true
  else
    say "• Size & rows (estimated)"
    run_sql "
      SELECT
        '${tbl}' AS table_name,
        pg_size_pretty(pg_total_relation_size('${DB_SCHEMA}.${tbl}')) AS total_size,
        (SELECT reltuples::bigint FROM pg_class WHERE oid='${DB_SCHEMA}.${tbl}'::regclass) AS est_rows;
    " || true
  fi
done

say ""
say "✅ Done. If tables show columns, indexes, constraints, sizes and row estimates, your DB is healthy."
