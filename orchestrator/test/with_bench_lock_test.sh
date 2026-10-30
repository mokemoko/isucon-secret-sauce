#!/usr/bin/env bash
# with-bench-lock.sh: 本番サーバのロックが空くまで待ってから実行し、終了コードを返し、ロックを離す。中のコマンドに BENCH_LOCK_TOKEN を渡す
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
# 偽の ssh: オプションとホスト名を捨ててローカルで実行する
printf '#!/usr/bin/env bash\nwhile [ "$1" = -o ]; do shift 2; done\nshift; exec bash -c "$*"\n' >"$t/bin/ssh"; chmod +x "$t/bin/ssh"
export PATH="$t/bin:$PATH" ENV_FILE=/nonexistent LOCK_HOST=h1 LOCK_PATH=$t/lock
mkdir "$t/lock"; echo "other 0 someone bench" >"$t/lock/owner"
( sleep 3; rm -rf "$t/lock" ) &
s=$(date +%s)
out=$(cd "$t" && "$root/bin/with-bench-lock.sh" sh -c 'test -d "$LOCK_PATH" && test -n "$BENCH_LOCK_TOKEN" && grep -q "$BENCH_LOCK_TOKEN" "$LOCK_PATH/owner" && pwd' 2>/dev/null)
[ $(( $(date +%s) - s )) -ge 2 ] || { echo "FAIL did not wait"; exit 1; }
[ "$out" = "$(cd "$t" && pwd -P)" ] || [ "$out" = "$t" ] || { echo "FAIL cwd/token: $out"; exit 1; }
[ ! -d "$t/lock" ] || { echo "FAIL lock left"; exit 1; }
rc=0; "$root/bin/with-bench-lock.sh" sh -c 'exit 3' || rc=$?
[ "$rc" = 3 ] && [ ! -d "$t/lock" ] || { echo "FAIL rc=$rc"; exit 1; }
# 入れ子: 呼び出し元がトークンを持っていれば、取り直さずにそのまま実行する (ロックが他人のものでも待たない)
mkdir "$t/lock"; echo "tok 0 x" >"$t/lock/owner"
BENCH_LOCK_TOKEN=tok "$root/bin/with-bench-lock.sh" true && [ -d "$t/lock" ] || { echo "FAIL nested"; exit 1; }
echo ok
