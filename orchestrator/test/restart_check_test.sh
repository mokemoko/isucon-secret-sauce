#!/usr/bin/env bash
# restart-check.sh: PROBE_URLS が空なら再起動しない / 起動完了と probe の一致を待ってからベンチ
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/bin"
# 偽の ssh: reboot で印を付け、起動中は is-system-running が starting を返す
cat >"$t/bin/ssh" <<'S'
#!/usr/bin/env bash
while [ "${1#-}" != "$1" ]; do shift 2; done; shift   # オプションとホスト名を捨てる
case $* in
  *"$T/lock"*) exec bash -c "$*" ;;   # bin/lock.sh のロック
  *reboot*) echo 2 >"$T/boot"; echo reboot >>"$T/log" ;;
  *is-system-running*) n=$(cat "$T/boot" 2>/dev/null || echo 0); if [ "$n" -gt 0 ]; then echo $((n-1)) >"$T/boot"; echo starting; else echo running; fi ;;
  *curl*) echo body ;;
esac
S
printf '#!/bin/sh\ngrep -q "^$BENCH_LOCK_TOKEN " "$T/lock/owner" && echo locked >>"$T/log"\necho "bench SKIP_DEPLOY=$SKIP_DEPLOY $*" >>"$T/log"\n' >"$t/bin/bench"
chmod +x "$t/bin/ssh" "$t/bin/bench"
export T=$t PATH="$t/bin:$PATH" BENCH_SH=$t/bin/bench REBOOT_GRACE=0 LOCK_PATH=$t/lock
env_file() { printf 'HOSTS="h1 h2"\nAPP_HOST=h1\nPROBE_URLS="%s"\n' "$1" >"$t/env.sh"; }

env_file ""
if ENV_FILE=$t/env.sh "$root/bin/restart-check.sh" x 2>/dev/null; then echo "FAIL: empty PROBE_URLS passed"; exit 1; fi
[ ! -f "$t/log" ] || { echo "FAIL: rebooted with empty PROBE_URLS"; exit 1; }

env_file "http://localhost/"
# sleep 5 を待たないよう、起動中の応答は1回だけにする
sed -i '' 's/echo 2 >"\$T\/boot"/echo 1 >"$T\/boot"/' "$t/bin/ssh"
ENV_FILE=$t/env.sh TIMEOUT=60 "$root/bin/restart-check.sh" x 2>/dev/null
[ "$(grep -c reboot "$t/log")" = 2 ] || { echo "FAIL: reboot count"; cat "$t/log"; exit 1; }
tail -1 "$t/log" | grep -q 'bench SKIP_DEPLOY=1 HEAD restart-check x' || { echo "FAIL: bench"; cat "$t/log"; exit 1; }
# 再起動からベンチまでロックを持ち、bench にトークンを渡し、終わったら離す
grep -qx locked "$t/log" && [ ! -d "$t/lock" ] || { echo "FAIL: lock"; cat "$t/log"; exit 1; }
echo ok
