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
TASK=t1 "$root/bin/bench.sh" origin/main first >/dev/null
line=$(tail -n1 "$STATE/bench.jsonl")
[ "$(echo "$line" | jq -r .score)" = 1234 ] || { echo "FAIL score: $line"; exit 1; }
[ "$(echo "$line" | jq -r .sha)" = "$sha" ] || { echo "FAIL sha: $line"; exit 1; }
[ "$(echo "$line" | jq -r .note)" = first ] || { echo "FAIL note: $line"; exit 1; }
[ "$(echo "$line" | jq -r .task)" = t1 ] || { echo "FAIL task: $line"; exit 1; }
id=$(echo "$line" | jq -r .id)
[ -f "$STATE/analysis/$id/h1/access.log" ] && [ ! -s "$STATE/analysis/$id/h1/access.log" ] || { echo "FAIL log not truncated/collected"; exit 1; }
[ ! -e "$STATE/analysis/$id/h1/missing-slow.log" ] || { echo "FAIL missing log should be skipped"; exit 1; }
[ ! -d "$STATE/bench.lock" ] || { echo "FAIL lock left"; exit 1; }
grep -q 'pass=true score=1234' "$STATE/analysis/$id/summary.md" || { echo "FAIL summary.md"; exit 1; }

# 2) ベンチコマンド失敗 → pass:false で記録される
sed -i '' 's|^BENCH_CMD=.*|BENCH_CMD=false|' "$t/env.sh"
"$root/bin/bench.sh" >/dev/null
[ "$(tail -n1 "$STATE/bench.jsonl" | jq -r .pass)" = false ] || { echo "FAIL failure not recorded"; exit 1; }

# 3) SKIP_DEPLOY → restart_check:true
sed -i '' 's|^BENCH_CMD=.*|BENCH_CMD=fakebench|' "$t/env.sh"
SKIP_DEPLOY=1 "$root/bin/bench.sh" HEAD >/dev/null
[ "$(tail -n1 "$STATE/bench.jsonl" | jq -r .restart_check)" = true ] || { echo "FAIL restart flag"; exit 1; }

# 4) 複数ホストの pprof → <host>/cpu.pprof。プロファイルとして壊れていても台帳には記録され、理由が digest.err に残る
echo notapprof >"$t/fake.pprof"
sed -i '' "s|^HOSTS=.*|HOSTS=\"h1 h2\"; APP_HOST=h1; REPO_DIR=$t/app; LOG_FILES=\"$t/access.log\"|; s|^PPROF_URL=.*|PPROF_URL=file://$t/fake.pprof; PPROF_HOSTS=\"h1 h2\"; PROBE_URLS=\"\"; ALP_ARGS=\"\"|" "$t/env.sh"
# deploy は飛ばす (fake ssh では2台が同じローカル repo を指し、並列 deploy の git lock が衝突するため)
SKIP_DEPLOY=1 "$root/bin/bench.sh" HEAD >/dev/null
id=$(tail -n1 "$STATE/bench.jsonl" | jq -r .id)
for h in h1 h2; do
  [ -s "$STATE/analysis/$id/$h/cpu.pprof" ] || { echo "FAIL pprof not collected for $h"; exit 1; }
done
grep -q 'profile: .*/h2/cpu.pprof の変換に失敗' "$STATE/analysis/$id/digest.err" || { echo "FAIL digest.err"; exit 1; }
[ "$(tail -n1 "$STATE/bench.jsonl" | jq -r .score)" = 1234 ] || { echo "FAIL bench not recorded after digest failure"; exit 1; }

# 5) psdigest: ベンチ前に TRUNCATE、ベンチ後に SELECT が DB ホストで呼ばれ、queries.json になる
cat >"$t/bin/fakemysql" <<EOF
#!/usr/bin/env bash
q=\$(cat); echo "\$q" | grep -q TRUNCATE && [ ! -f "$t/bench.ran" ] && echo truncated >"$t/mysql.log"   # ベンチ前のリセットだけ数える
echo "\$q" | grep -q SELECT && [ -f "$t/mysql.log" ] && [ -f "$t/bench.ran" ] && printf 'SELECT ?\t3\t3000000000000\t1000000000000\t1000000000000\t1000000000000\t3\t3\t0\t0\t0\t0\tSELECT 1\n'
true
EOF
printf '#!/bin/sh\ntouch %s\necho %s\n' "$t/bench.ran" "'{\"pass\":true,\"score\":1}'" >"$t/bin/fakebench2"; chmod +x "$t/bin/fakemysql" "$t/bin/fakebench2"
sed -i '' "s|^BENCH_CMD=.*|BENCH_CMD=fakebench2; QUERY_DIGEST=psdigest; DB_HOSTS=h2; MYSQL_CMD=fakemysql|; s|^PPROF_URL=.*|PPROF_URL=\"\"; PROBE_URLS=\"\"; ALP_ARGS=\"\"|" "$t/env.sh"
SKIP_DEPLOY=1 "$root/bin/bench.sh" HEAD >/dev/null
id=$(tail -n1 "$STATE/bench.jsonl" | jq -r .id)
[ "$(jq -r '.[0] | "\(.fingerprint) \(.count) \(.sum)"' "$STATE/analysis/$id/h2/queries.json")" = "SELECT ? 3 3" ] || { echo "FAIL psdigest flow"; exit 1; }

# 6) EXTRA_COLLECT: dns-pdns.collect.sh がベンチ前後に統計 API を取り、dns.json が差分になる。アプリの extcmd.log は LOG_FILES で回収されて extcmd.json になる
cat >"$t/bin/curl" <<EOF
#!/usr/bin/env bash
n=100; [ -f "$t/bench.ran" ] && n=160
echo "[{\"name\":\"udp-queries\",\"type\":\"StatisticItem\",\"value\":\"\$n\"},{\"name\":\"uptime\",\"type\":\"StatisticItem\",\"value\":\"\$n\"},{\"name\":\"latency\",\"type\":\"StatisticItem\",\"value\":\"50\"}]"
EOF
chmod +x "$t/bin/curl"; rm -f "$t/bench.ran"
echo '{"cmd":"old","sec":9}' >"$t/extcmd.log"
printf '#!/bin/sh
touch %s
echo %s >>%s
echo %s
' "$t/bench.ran" "'{\"cmd\":\"dnsctl add\",\"sec\":0.25}'" "$t/extcmd.log" "'{\"pass\":true,\"score\":1}'" >"$t/bin/fakebench3"; chmod +x "$t/bin/fakebench3"
sed -i '' "s|^HOSTS=.*|HOSTS=\"h1\"; APP_HOST=h1; REPO_DIR=$t/app; LOG_FILES=\"$t/access.log $t/extcmd.log\"|; s|^BENCH_CMD=.*|BENCH_CMD=fakebench3; EXTRA_COLLECT=dns-pdns; PDNS_API_KEY=k|" "$t/env.sh"
SKIP_DEPLOY=1 "$root/bin/bench.sh" HEAD >/dev/null
id=$(tail -n1 "$STATE/bench.jsonl" | jq -r .id)
[ "$(jq -c '{sec, q: .queries.udp, l: .latency_us.all}' "$STATE/analysis/$id/h1/dns.json")" = '{"sec":60,"q":60,"l":50}' ] || { echo "FAIL dns flow"; exit 1; }
[ "$(jq -c 'map([.cmd, .count])' "$STATE/analysis/$id/h1/extcmd.json")" = '[["dnsctl add",1]]' ] || { echo "FAIL extcmd flow"; exit 1; }
grep -q '^queries=60 (udp 60 tcp null、1/s)' "$STATE/analysis/$id/summary.md" && grep -q '^## extcmd h1' "$STATE/analysis/$id/summary.md" || { echo "FAIL dns/extcmd summary"; cat "$STATE/analysis/$id/summary.md"; exit 1; }

echo "ok"
