#!/usr/bin/env bash
# usage: query-pgss.collect.sh <pre|post> <host> <出力ディレクトリ>
# PostgreSQL の pg_stat_statements を、ベンチ前にリセットし、ベンチ後に上位 30 種を TSV で取る (<出力>/query-pgss.raw)。
# 前提: shared_preload_libraries に pg_stat_statements (要再起動)、対象 DB で CREATE EXTENSION pg_stat_statements。
# PSQL_CMD (既定 "sudo -u postgres psql -X") はサーバ上で superuser の psql を起動するコマンド (-d <db> を足してよい)
set -euo pipefail
phase=$1 host=$2 out=$3
p=${PSQL_CMD:-sudo -u postgres psql -X}
case $phase in
  pre) echo 'SELECT pg_stat_statements_reset();' | ssh "$host" "$p -q -A -t" >/dev/null ;;
  post) mkdir -p "$out"; ssh "$host" "$p -q -A -t -F \$'\\t'" >"$out/query-pgss.raw" <<'SQL'
SELECT regexp_replace(query, '\s+', ' ', 'g'), calls, total_exec_time, mean_exec_time, max_exec_time, stddev_exec_time, rows, shared_blks_hit, shared_blks_read
FROM pg_stat_statements
WHERE query NOT ILIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC LIMIT 30;
SQL
  ;;
  *) echo "usage: $0 <pre|post> <host> <dir>" >&2; exit 2 ;;
esac
