#!/usr/bin/env bash
# local-env.sh: name ごとに決まった値を .env に書き、2回目は変えない。git の除外に入る
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q
a=$("$root/bin/local-env.sh" "impl-Task_ABC")
echo "$a" | grep -qx 'COMPOSE_PROJECT_NAME=impl-task_abc' || { echo "FAIL name: $a"; exit 1; }
p=$(sed -n 's/^LOCAL_PORT=//p' local/.env)
[ "$p" -ge 20000 ] && [ "$p" -le 59990 ] || { echo "FAIL port $p"; exit 1; }
grep -qx "LOCAL_DB_PORT=$((p + 1))" local/.env || { echo "FAIL db port"; exit 1; }
echo 'LOCAL_PORT=1' >local/.env; "$root/bin/local-env.sh" "impl-Task_ABC" | grep -qx 'LOCAL_PORT=1' || { echo "FAIL idempotent"; exit 1; }
git status --porcelain | grep -q 'local/' && { echo "FAIL not excluded"; exit 1; }
b=$("$root/bin/local-env.sh" other x); [ "$(echo "$b" | sed -n 's/^LOCAL_PORT=//p')" != "$p" ] || { echo "FAIL same port for other name"; exit 1; }
echo ok
