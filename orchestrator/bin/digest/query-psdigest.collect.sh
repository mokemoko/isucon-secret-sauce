#!/usr/bin/env bash
# usage: query-psdigest.collect.sh <pre|post> <host> <出力ディレクトリ>
# MySQL 8.0 の performance_schema の digest 集計を、ベンチ前にリセットし、ベンチ後に上位 30 種を TSV で取る (<出力>/query-psdigest.raw)。
# MYSQL_CMD (既定 "sudo mysql") はサーバ上で root 権限の mysql クライアントを起動するコマンド。TRUNCATE には DROP 権限が要る。
# MariaDB は QUANTILE_95 / QUERY_SAMPLE_TEXT が無く既定で無効なので、QUERY_DIGEST=pt (slow log) を使う
set -euo pipefail
phase=$1 host=$2 out=$3
m=${MYSQL_CMD:-sudo mysql}
case $phase in
  pre) echo 'TRUNCATE TABLE performance_schema.events_statements_summary_by_digest;' | ssh "$host" "$m" ;;
  post) mkdir -p "$out"; ssh "$host" "$m -B -N" >"$out/query-psdigest.raw" <<'SQL'
SELECT DIGEST_TEXT, COUNT_STAR, SUM_TIMER_WAIT, AVG_TIMER_WAIT, MAX_TIMER_WAIT, QUANTILE_95,
  SUM_ROWS_EXAMINED, SUM_ROWS_SENT, SUM_NO_INDEX_USED, SUM_NO_GOOD_INDEX_USED, SUM_CREATED_TMP_DISK_TABLES, SUM_LOCK_TIME, QUERY_SAMPLE_TEXT
FROM performance_schema.events_statements_summary_by_digest
WHERE DIGEST_TEXT IS NOT NULL AND DIGEST_TEXT NOT LIKE '%performance_schema%' AND DIGEST_TEXT NOT LIKE 'SELECT @@%'
ORDER BY SUM_TIMER_WAIT DESC LIMIT 30;
SQL
  ;;
  *) echo "usage: $0 <pre|post> <host> <dir>" >&2; exit 2 ;;
esac
