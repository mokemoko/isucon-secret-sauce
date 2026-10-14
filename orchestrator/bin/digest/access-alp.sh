#!/usr/bin/env bash
# usage: access-alp.sh <access.log> <raw出力先>
# アクセスログ → endpoints スキーマ (stdout)。ALP_ARGS (例 "json --config alp.yml") でログ形式と URI 正規化を指定する
set -euo pipefail
log=$1 raw=$2
alp $ALP_ARGS --file "$log" >"$raw"
alp $ALP_ARGS --format json --file "$log" | jq '
  .[0] as $h | .[1:] | map([$h, .] | transpose | map({(.[0]): .[1]}) | add) | map({
    method, uri, count,
    status: {"1xx": ."1xx", "2xx": ."2xx", "3xx": ."3xx", "4xx": ."4xx", "5xx": ."5xx"},
    sum, avg, max, p90, p95, p99, body_sum: .sum_body, body_avg: .avg_body
  }) | sort_by(-.sum)'
