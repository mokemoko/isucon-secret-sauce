#!/usr/bin/env bash
# usage: bin/bench.sh [ref=origin/main] [note]
# 直列 bench lane: deploy → ログ truncate → bench (+pprof) → ログ回収・解析 → state/bench.jsonl に1行追記
# TASK=<orca task id> PREDICTED=<ローカル軽量ベンチでの改善率 %> を渡すと台帳に残り、予測と実績のギャップ分析に使う
# SKIP_DEPLOY=1 で deploy を飛ばす (再起動確認用。deploy の service restart が起動確認を潰すため)
set -euo pipefail
cd "$(dirname "$0")/.."
. "${ENV_FILE:-./env.sh}"
ref=${1:-origin/main}; note=${2:-}
STATE=${STATE:-state}
mkdir -p "$STATE"

# ponytail: mkdir ロック (macOS に flock が無い)。異常終了で残ったら state/bench.lock を手で消す
until mkdir "$STATE/bench.lock" 2>/dev/null; do sleep 2; done
trap 'rmdir "$STATE/bench.lock"' EXIT

if [ "${SKIP_DEPLOY:-}" = 1 ]; then
  sha=$(ssh "$APP_HOST" "cd $REPO_DIR && git rev-parse HEAD")
else
  sha=$(bin/deploy.sh "$ref")
fi
id=$(date +%H%M%S)-${sha:0:7}
dir="$STATE/analysis/$id"
mkdir -p "$dir"

for h in $HOSTS; do
  ssh "$h" "for f in $LOG_FILES; do sudo test -f \$f && sudo truncate -s0 \$f; done; true"
done

pprof_pid=
if [ -n "$PPROF_URL" ]; then
  ssh "$APP_HOST" "curl -s '$PPROF_URL'" >"$dir/cpu.pprof" & pprof_pid=$!
fi
if $BENCH_CMD >"$dir/bench.txt" 2>"$dir/bench.err"; then
  result=$(tail -n1 "$dir/bench.txt")
  echo "$result" | jq -e 'has("pass") and has("score")' >/dev/null || result='{"pass":false,"score":0,"error":"unparsable bench output"}'
else
  result='{"pass":false,"score":0,"error":"bench command failed"}'
fi
[ -z "$pprof_pid" ] || wait "$pprof_pid" || true

for h in $HOSTS; do
  mkdir -p "$dir/$h"
  for f in $LOG_FILES; do
    ssh "$h" "sudo test -f $f && sudo cat $f" >"$dir/$h/$(basename "$f")" 2>/dev/null || rm -f "$dir/$h/$(basename "$f")"
  done
done
# 解析ツールが無ければ生ログだけ残す
for f in "$dir"/*/access.log; do
  [ -f "$f" ] && command -v alp >/dev/null && alp $ALP_ARGS --file "$f" >"${f%.log}.alp.txt" 2>&1 || true
done
for f in "$dir"/*/*slow*.log; do
  [ -f "$f" ] && command -v pt-query-digest >/dev/null && pt-query-digest "$f" >"${f%.log}.pt.txt" 2>&1 || true
done

jq -cn --arg id "$id" --arg ts "$(date -u +%FT%TZ)" --arg sha "$sha" --arg note "$note" \
  --arg restart "${SKIP_DEPLOY:-0}" --arg task "${TASK:-}" --arg pred "${PREDICTED:-}" --argjson r "$result" \
  '{id:$id, ts:$ts, sha:$sha, note:$note, restart_check:($restart=="1"), task:$task,
    predicted:(if $pred=="" then null else ($pred|tonumber) end)} + $r' | tee -a "$STATE/bench.jsonl"
