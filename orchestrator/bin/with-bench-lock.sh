#!/usr/bin/env bash
# usage: bin/with-bench-lock.sh <cmd> [args...]
# bench.sh と同じロック ($STATE/bench.lock) を取ってから <cmd> を実行し、終わったら離す。本番サーバに触る作業 (ブラウザでの確認など) をベンチと重ねないため
# ベンチ枠を止めるので、1回は短く (画面1つ・操作1つ程度) する。60秒を超えたら標準エラーに警告を出す
set -uo pipefail
cd "$(dirname "$0")/.."
STATE=${STATE:-state}
[ $# -gt 0 ] || { echo "usage: with-bench-lock.sh <cmd> [args...]" >&2; exit 2; }
until mkdir "$STATE/bench.lock" 2>/dev/null; do sleep 2; done
trap 'rmdir "$STATE/bench.lock"' EXIT
cd "${OLDPWD:-.}"   # 呼び出し元のディレクトリでコマンドを実行する
t0=$(date +%s)
"$@"; rc=$?
d=$(( $(date +%s) - t0 ))
[ "$d" -gt 60 ] && echo "with-bench-lock: ロックを ${d} 秒持った (ベンチ枠を止めている。1回を短くする)" >&2
exit $rc
