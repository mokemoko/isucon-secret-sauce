#!/usr/bin/env bash
# bench lane の通し確認。ssh をローカル実行に差し替え、一時 git repo を「サーバ」に見立てる
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# fake ssh: 第1引数(host)と -o オプションを捨て、sudo を外してローカル実行
mkdir "$t/bin"
cat >"$t/bin/ssh" <<'EOF'
#!/usr/bin/env bash
while [ "$1" = -o ]; do shift 2; done
shift; c="$*"; exec bash -c "${c//sudo /}"
EOF
chmod +x "$t/bin/ssh"
export PATH="$t/bin:$PATH"

git init -q --bare "$t/origin.git"
git clone -q "$t/origin.git" "$t/app" 2>/dev/null
printf 'deploy:\n\t@echo deployed\n' >"$t/app/Makefile"
git -C "$t/app" add . && git -C "$t/app" -c user.name=t -c user.email=t@t commit -qm init && git -C "$t/app" push -q origin HEAD:main
sha=$(git -C "$t/app" rev-parse HEAD)
echo "old log line" >"$t/access.log"

cat >"$t/env.sh" <<EOF
HOSTS="h1"; APP_HOST=h1; REPO_DIR=$t/app; LOG_FILES="$t/access.log $t/missing-slow.log"
BENCH_CMD=fakebench
PPROF_URL=""; PROBE_URLS=""; ALP_ARGS=""
EOF
export ENV_FILE="$t/env.sh" STATE="$t/state"
# BENCH_CMD は単語分割で実行されるので、複合コマンドはスクリプトにする
printf '#!/bin/sh\necho progress\necho %s\n' "'{\"pass\":true,\"score\":1234}'" >"$t/bin/fakebench"; chmod +x "$t/bin/fakebench"

# 1) 成功ケース
TASK=t1 PREDICTED=12.5 "$root/bin/bench.sh" origin/main first >/dev/null
line=$(tail -n1 "$STATE/bench.jsonl")
[ "$(echo "$line" | jq -r .score)" = 1234 ] || { echo "FAIL score: $line"; exit 1; }
[ "$(echo "$line" | jq -r .sha)" = "$sha" ] || { echo "FAIL sha: $line"; exit 1; }
[ "$(echo "$line" | jq -r .note)" = first ] || { echo "FAIL note: $line"; exit 1; }
[ "$(echo "$line" | jq -c "[.task,.predicted]")" = '["t1",12.5]' ] || { echo "FAIL prediction: $line"; exit 1; }
id=$(echo "$line" | jq -r .id)
[ -f "$STATE/analysis/$id/h1/access.log" ] && [ ! -s "$STATE/analysis/$id/h1/access.log" ] || { echo "FAIL log not truncated/collected"; exit 1; }
[ ! -e "$STATE/analysis/$id/h1/missing-slow.log" ] || { echo "FAIL missing log should be skipped"; exit 1; }
[ ! -d "$STATE/bench.lock" ] || { echo "FAIL lock left"; exit 1; }

# 2) ベンチコマンド失敗 → pass:false で記録される
sed -i '' 's|^BENCH_CMD=.*|BENCH_CMD=false|' "$t/env.sh"
"$root/bin/bench.sh" >/dev/null
[ "$(tail -n1 "$STATE/bench.jsonl" | jq -r .pass)" = false ] || { echo "FAIL failure not recorded"; exit 1; }

# 3) SKIP_DEPLOY → restart_check:true
sed -i '' 's|^BENCH_CMD=.*|BENCH_CMD=fakebench|' "$t/env.sh"
SKIP_DEPLOY=1 "$root/bin/bench.sh" HEAD >/dev/null
[ "$(tail -n1 "$STATE/bench.jsonl" | jq -r .restart_check)" = true ] || { echo "FAIL restart flag"; exit 1; }

echo "ok"
