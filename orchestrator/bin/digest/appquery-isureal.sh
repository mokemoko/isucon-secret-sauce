#!/usr/bin/env bash
# usage: appquery-isureal.sh <appquery-isureal.raw> <元の出力の保存先>
# アプリの /debug/querystats (query_stats.go) → <host>/appquery.json (stdout)。時間は秒
#   {sec, pool:{max_open, open, in_use, wait_count, wait_sec}, routes:[{route, count, sum, avg, p95, queries, db_sum, queries_avg, db_avg}] db_sum 降順,
#    queries:[{query, count, errors, sum, avg, p95, max}] sum 降順}
# アプリから見た時間なので、DB 内の時間 (DB ホストの queries.json) との差がルーター越しの往復・行の転送・接続の取り合い
set -euo pipefail
in=$1 raw=$2
cp "$in" "$raw"
jq '{sec, pool, routes: (.routes // [] | sort_by(-.db_sum)), queries: (.queries // [] | sort_by(-.sum))}' "$in"
