#!/usr/bin/env bash
# usage: extcmd-jsonl.sh <extcmd.log> <元の出力の保存先>
# アプリが書いた外部コマンドの実行時間 (1行 {"cmd":..., "sec":..., "err":bool}) を cmd ごとに集計する。
#   [{cmd, count, errors, sum, avg, p95, max}] 秒・sum 降順。JSON でない行は捨てる
set -euo pipefail
in=$1 raw=$2
jq -R 'fromjson? | select(type == "object" and .cmd and .sec)' "$in" | jq -s '
  group_by(.cmd) | map((map(.sec) | sort) as $s | {cmd: .[0].cmd, count: length, errors: map(select(.err)) | length,
    sum: ($s | add), avg: ($s | add / length), p95: $s[((length * 0.95 | ceil) - 1)], max: $s[-1]}) | sort_by(-.sum)' | tee "$raw"
