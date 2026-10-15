#!/usr/bin/env bash
# stalled-workers.sh: activity=done の dispatched を初めて見た時刻から STALL_MIN 分たったら出し、止まっていなくなったら消す
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export STATE=$t ORCA=$t/orca; echo run_x >"$t/run_id"
cat >"$t/orca" <<'S'
#!/bin/sh
cat "$(dirname "$0")/workers.json"
S
chmod +x "$t/orca"
w() { echo "{\"result\":{\"workers\":[$1]}}" >"$t/workers.json"; }
stuck='{"dispatchId":"ctx_a","agentTerminalHandle":"term_a","taskId":"task_a","dispatchStatus":"dispatched","projection":{"stage":{"activity":"done"}}}'
busy='{"dispatchId":"ctx_b","agentTerminalHandle":"term_b","taskId":"task_b","dispatchStatus":"dispatched","projection":{"stage":{"activity":"working"}}}'
w "$stuck,$busy"
[ -z "$("$root/bin/stalled-workers.sh")" ] || { echo "FAIL reported too early"; exit 1; }
out=$(STALL_MIN=0 "$root/bin/stalled-workers.sh")
[ "$out" = "0 term_a task_a ctx_a" ] || { echo "FAIL: $out"; exit 1; }
# 初めて見た時刻を引き継ぐ: 10分前に見たことにする
awk -F'\t' -v OFS='\t' '{ $2 = $2 - 600; print }' "$t/stalled.tsv" >"$t/x" && mv "$t/x" "$t/stalled.tsv"
[ "$("$root/bin/stalled-workers.sh" | cut -d' ' -f1)" = 10 ] || { echo "FAIL keep first seen"; exit 1; }
# 動き出したら消える
w "$busy"; [ -z "$(STALL_MIN=0 "$root/bin/stalled-workers.sh")" ] && [ ! -s "$t/stalled.tsv" ] || { echo "FAIL clear"; exit 1; }
echo ok
