#!/usr/bin/env bash
# usage: query-pt.sh <slow.log> <raw出力先>
# MySQL/MariaDB の slow log → queries スキーマ (stdout)
set -euo pipefail
log=$1 raw=$2
# --progress: 30秒ごとの進捗表示が stderr (digest.err) に混ざるのを止める
pt-query-digest --progress time,86400 "$log" >"$raw"
pt-query-digest --progress time,86400 --output json --limit 30 "$log" | jq '
  def n: tonumber? // 0;
  [.classes[] | .metrics as $m | {
    fingerprint, count: .query_count,
    sum: ($m.Query_time.sum|n), avg: ($m.Query_time.avg|n), p95: ($m.Query_time.pct_95|n), max: ($m.Query_time.max|n),
    rows_examined_avg: ($m.Rows_examined.avg|n), rows_sent_avg: ($m.Rows_sent.avg|n),
    sample: (.example.query // "" | .[0:300])
  }] | sort_by(-.sum)'
