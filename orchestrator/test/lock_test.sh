#!/usr/bin/env bash
# lock.sh: 本番サーバ上の mkdir ロック。自分のトークンのときだけ離す、持ち主と経過秒を出す
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bin"
printf '#!/usr/bin/env bash\nwhile [ "$1" = -o ]; do shift 2; done\nshift; exec bash -c "$*"\n' >"$t/bin/ssh"; chmod +x "$t/bin/ssh"
export PATH="$t/bin:$PATH" ENV_FILE=/nonexistent LOCK_HOST=h1 LOCK_PATH=$t/lock
l=$root/bin/lock.sh

[ "$($l status)" = free ] && [ "$($l status --json)" = '{"held":false}' ] || { echo "FAIL free"; exit 1; }
tok=$(LOCK_WHO=alice $l acquire "手で sysctl")
[ -n "$tok" ] && [ -d "$t/lock" ] || { echo "FAIL acquire"; exit 1; }
$l status | grep -qE '^held [0-9]+s alice 手で sysctl$' || { echo "FAIL status: $($l status)"; exit 1; }
[ "$($l status --json | jq -r '.held, .who' | paste -sd' ' -)" = "true alice 手で sysctl" ] || { echo "FAIL status json"; exit 1; }
# 他人のトークンでは離さない
$l release wrong 2>"$t/err"; [ -d "$t/lock" ] && grep -q '自分のロックではない' "$t/err" || { echo "FAIL released by other"; exit 1; }
# 取られている間は待つ
( sleep 3; $l release "$tok" ) &
s=$(date +%s); tok2=$($l acquire second 2>/dev/null)
[ $(( $(date +%s) - s )) -ge 2 ] && [ "$tok2" != "$tok" ] || { echo "FAIL wait"; exit 1; }
wait
$l release "$tok2" && [ ! -d "$t/lock" ] || { echo "FAIL release"; exit 1; }
# break は持ち主に関係なく消す
$l acquire x >/dev/null; $l break; [ ! -d "$t/lock" ] || { echo "FAIL break"; exit 1; }
# ホストが分からなければ使えない
if LOCK_HOST= $l status 2>/dev/null; then echo "FAIL no host"; exit 1; fi
echo ok
