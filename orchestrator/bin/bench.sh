#!/usr/bin/env bash
# usage: bin/bench.sh [ref=origin/main] [note]
# 直列 bench lane: deploy → ログ truncate → bench (+pprof) → ログ回収・bin/digest.sh で解析 → state/bench.jsonl に1行追記
# TASK=<orca task id (カンマ区切り可)> を渡すと台帳に残る
# SKIP_DEPLOY=1 で deploy を飛ばす (再起動確認用。deploy の service restart が起動確認を潰すため)
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . "${ENV_FILE:-./env.sh}"; set +a   # アダプタ (bin/digest/*) にも MYSQL_CMD 等を渡す
QUERY_DIGEST=${QUERY_DIGEST:-pt}
ref=${1:-origin/main}; note=${2:-}
STATE=${STATE:-state}
mkdir -p "$STATE"

# 本番サーバのロック (bin/lock.sh。オーケストレータの外で作業する人と共有)。呼び出し元が持っていれば (BENCH_LOCK_TOKEN) そのまま使う
# 異常終了で残ったら bin/lock.sh status で持ち主を確かめ、bin/lock.sh break で消す
if [ -z "${BENCH_LOCK_TOKEN:-}" ]; then
  BENCH_LOCK_TOKEN=$(bin/lock.sh acquire "bench $note")
  trap 'bin/lock.sh release "$BENCH_LOCK_TOKEN"' EXIT
  trap 'exit 130' INT TERM
fi

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

# クエリ集計をベンチ単位にする (アダプタに collect があれば、DB ホストでベンチ前にリセット・ベンチ後に取得)
collect() {
  local c=bin/digest/query-$QUERY_DIGEST.collect.sh h
  [ -x "$c" ] || return 0
  for h in ${DB_HOSTS:-$APP_HOST}; do "$c" "$1" "$h" "$dir/$h" 2>>"$dir/collect.err" || echo "collect $1 $h 失敗" >>"$dir/collect.err"; done
}
# 追加の計測 (env.sh の EXTRA_COLLECT。bin/digest/<名前>.collect.sh を EXTRA_COLLECT_HOSTS (既定 APP_HOST) でベンチ前後に呼ぶ。例 dns-pdns)
extra() {
  local k h
  for k in ${EXTRA_COLLECT:-}; do
    for h in ${EXTRA_COLLECT_HOSTS:-$APP_HOST}; do
      "bin/digest/$k.collect.sh" "$1" "$h" "$dir/$h" 2>>"$dir/collect.err" || echo "collect $k $1 $h 失敗" >>"$dir/collect.err"
    done
  done
}
collect pre; extra pre

# ベンチ中のリソース推移 (各ホストで1秒ごとに /proc を読む)。ベンチ後に ssh を kill して止める
sampler_pids=
if [ "${RESOURCE_SAMPLING:-1}" = 1 ]; then
  for h in $HOSTS; do
    mkdir -p "$dir/$h"
    ssh "$h" "SAMPLER_ID=$id timeout 1800 bash -s" <bin/sample-resources.sh >"$dir/$h/resources.raw" 2>/dev/null & sampler_pids="$sampler_pids $!"
  done
fi
pprof_pids=
if [ -n "$PPROF_URL" ]; then
  for h in ${PPROF_HOSTS:-$APP_HOST}; do
    mkdir -p "$dir/$h"
    ssh "$h" "curl -s '$PPROF_URL'" >"$dir/$h/cpu.pprof" & pprof_pids="$pprof_pids $!"
  done
fi
if $BENCH_CMD >"$dir/bench.txt" 2>"$dir/bench.err"; then
  result=$(tail -n1 "$dir/bench.txt")
  echo "$result" | jq -e 'has("pass") and has("score")' >/dev/null || result='{"pass":false,"score":0,"error":"unparsable bench output"}'
else
  result='{"pass":false,"score":0,"error":"bench command failed"}'
fi
for p in $pprof_pids; do wait "$p" || true; done
collect post; extra post
if [ -n "$sampler_pids" ]; then
  for h in $HOSTS; do ssh "$h" "f=/tmp/isu-sampler-$id.pid; [ -f \$f ] && kill \$(cat \$f)" 2>/dev/null || true; done
  for p in $sampler_pids; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
fi

for h in $HOSTS; do
  mkdir -p "$dir/$h"
  for f in $LOG_FILES; do
    ssh "$h" "sudo test -f $f && sudo cat $f" >"$dir/$h/$(basename "$f")" 2>/dev/null || rm -f "$dir/$h/$(basename "$f")"
  done
done
# 共通スキーマへの変換と summary.md。失敗しても台帳への記録は続ける (理由は digest.err)
bin/digest.sh "$dir" "$result" || true

jq -cn --arg id "$id" --arg ts "$(date -u +%FT%TZ)" --arg sha "$sha" --arg note "$note" \
  --arg restart "${SKIP_DEPLOY:-0}" --arg task "${TASK:-}" --argjson r "$result" \
  '{id:$id, ts:$ts, sha:$sha, note:$note, restart_check:($restart=="1"), task:$task} + $r' | tee -a "$STATE/bench.jsonl"
