#!/usr/bin/env bash
# usage: bin/stalled-workers.sh   (Coordinator がメインループのタイムアウトのたびに実行する)
# worker_done を送らずにターンを終えたワーカー (API エラーで応答が途切れた等) を出す。
# Orca 上は dispatched のままで、projection.stage.activity だけが done になる。Coordinator の check には何も届かない
# activity=done の dispatched のワーカーを初めて見た時刻を $STATE/stalled.tsv に残し、STALL_MIN 分 (既定 5) 続いたものを出す
#   出力 (1行1件): <分> <terminal handle> <task_id> <dispatch_id>   → orca terminal send で再開か worker_done を促す
set -uo pipefail
cd "$(dirname "$0")/.."
STATE=${STATE:-state}; ORCA=${ORCA:-orca}
run=$(cat "$STATE/run_id" 2>/dev/null) || { echo "run_id が無い" >&2; exit 1; }
f=$STATE/stalled.tsv; touch "$f"; now=$(date +%s)
cur=$("$ORCA" orchestration worker-list --run "$run" --terminal-state active --limit 100 --json 2>/dev/null \
  | jq -r '.result.workers[]? | select(.dispatchStatus == "dispatched" and .projection.stage.activity == "done")
      | [.dispatchId, .agentTerminalHandle, .taskId] | @tsv') || { echo "worker-list に失敗" >&2; exit 1; }
# 今も止まっているものだけ残す (初めて見た時刻は引き継ぐ)
{ while IFS=$'\t' read -r d h t; do
    [ -n "$d" ] || continue
    seen=$(awk -F'\t' -v d="$d" '$1 == d {print $2}' "$f"); printf '%s\t%s\t%s\t%s\n' "$d" "${seen:-$now}" "$h" "$t"
  done <<<"$cur"; } >"$f.tmp" && mv "$f.tmp" "$f"
awk -F'\t' -v now="$now" -v m="${STALL_MIN:-5}" '(now - $2) / 60 >= m { printf "%d %s %s %s\n", (now - $2) / 60, $3, $4, $1 }' "$f"
