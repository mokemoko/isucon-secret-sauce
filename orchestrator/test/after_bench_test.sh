#!/usr/bin/env bash
# ベンチ後のまとめ: 判定・警告の増減・ボトルネックの移動・再起動確認の要否・列の順位を1回で出す
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export STATE=$t
printf '%s\n' '{"id":"b1","sha":"s1","pass":true,"score":100}' '{"id":"b2","sha":"s2","pass":true,"score":120}' >"$t/bench.jsonl"
mk() { # id endpoint_uri query proc warnings
  mkdir -p "$t/analysis/$1/h1"
  echo "[{\"method\":\"GET\",\"uri\":\"$2\",\"sum\":10,\"weight\":1},{\"method\":\"GET\",\"uri\":\"/other\",\"sum\":1,\"weight\":1}]" >"$t/analysis/$1/h1/endpoints.json"
  echo "[{\"fingerprint\":\"$3\",\"sum\":5}]" >"$t/analysis/$1/h1/queries.json"
  echo "{\"ncpu\":2,\"procs\":[{\"comm\":\"$4\",\"cpu_avg\":90}]}" >"$t/analysis/$1/h1/resources.json"
  seq "$5" | sed 's/^/level=WARN /' >"$t/analysis/$1/warnings.txt"
}
mk b1 /a 'SELECT 1' mysqld 2
mk b2 /b 'SELECT 1' mysqld 5
printf 'task_x\tabc\t%s\n' "$(( $(date +%s) - 3000 ))" >"$t/restart-pending.tsv"
echo '[]' >"$t/merge-queue.json"
out=$(cd "$t" && "$root/bin/after-bench.sh" b2)
for want in 'verdict=adopt' '前回の pass ベンチ: b1' 'warnings=5 (前回 2) warnings_increased=yes' 'moved=yes' 'endpoint: GET /a -> GET /b' \
  'query: SELECT 1 (変わらず)' 'process: h1:mysqld (変わらず)' 'pending=1 最古=50分前 restart_check_due=yes' '基準ベンチ: b2'; do
  echo "$out" | grep -qF -- "$want" || { echo "FAIL '$want':"; echo "$out"; exit 1; }
done
# 変わらなければ moved=no、警告が減れば increased=no、pending が無ければ due=no
mk b2 /a 'SELECT 1' mysqld 1; : >"$t/restart-pending.tsv"
out=$(cd "$t" && "$root/bin/after-bench.sh" b2)
for want in 'moved=no' 'warnings_increased=no' 'pending=0 restart_check_due=no'; do
  echo "$out" | grep -qF -- "$want" || { echo "FAIL '$want':"; echo "$out"; exit 1; }
done
# 前回の pass ベンチが無い・解析結果が無いときも最後まで出す
out=$(cd "$t" && "$root/bin/after-bench.sh" b1)
echo "$out" | grep -qF 'moved=不明' && echo "$out" | grep -qF '## マージ待ちの列' || { echo "FAIL first bench:"; echo "$out"; exit 1; }
echo ok
