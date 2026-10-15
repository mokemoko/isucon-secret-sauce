#!/usr/bin/env bash
# with-bench-lock.sh: ロックが空くまで待ってから実行し、終了コードを返し、ロックを離す
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export STATE=$t
mkdir "$t/bench.lock"
( sleep 3; rmdir "$t/bench.lock" ) &
s=$(date +%s)
out=$(cd "$t" && "$root/bin/with-bench-lock.sh" sh -c 'test -d "$STATE/bench.lock" && pwd')
[ $(( $(date +%s) - s )) -ge 2 ] || { echo "FAIL did not wait"; exit 1; }
[ "$out" = "$(cd "$t" && pwd -P)" ] || [ "$out" = "$t" ] || { echo "FAIL cwd: $out"; exit 1; }
[ ! -d "$t/bench.lock" ] || { echo "FAIL lock left"; exit 1; }
rc=0; "$root/bin/with-bench-lock.sh" sh -c 'exit 3' || rc=$?
[ "$rc" = 3 ] && [ ! -d "$t/bench.lock" ] || { echo "FAIL rc=$rc"; exit 1; }
echo ok
