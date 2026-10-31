#!/usr/bin/env bash
# usage: bin/with-bench-lock.sh <cmd> [args...]
# bench.sh と同じ本番サーバのロック (bin/lock.sh) を取ってから <cmd> を実行し、終わったら離す。本番サーバに触る作業 (ブラウザでの確認、
# オーケストレータの外の人の手作業など) をベンチと重ねないため。<cmd> には BENCH_LOCK_TOKEN を渡すので、中で bench.sh を呼んでもよい
# ベンチ枠を止めるので、1回は短く (画面1つ・操作1つ程度) する。60秒を超えたら標準エラーに警告を出す
# LOCK_NOTE で何をするかを書ける (既定は <cmd>)。lock.sh status とダッシュボードに出る
set -uo pipefail
[ $# -gt 0 ] || { echo "usage: with-bench-lock.sh <cmd> [args...]" >&2; exit 2; }
[ -n "${BENCH_LOCK_TOKEN:-}" ] && exec "$@"   # 呼び出し元がすでに持っている
lock=$(cd "$(dirname "$0")" && pwd)/lock.sh
BENCH_LOCK_TOKEN=$("$lock" acquire "${LOCK_NOTE:-$*}") || exit 1
export BENCH_LOCK_TOKEN
trap '"$lock" release "$BENCH_LOCK_TOKEN"' EXIT
trap 'exit 130' INT TERM
t0=$(date +%s)
"$@"; rc=$?
d=$(( $(date +%s) - t0 ))
[ "$d" -gt 60 ] && echo "with-bench-lock: ロックを ${d} 秒持った (ベンチ枠を止めている。1回を短くする)" >&2
exit $rc
