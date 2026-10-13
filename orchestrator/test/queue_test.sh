#!/usr/bin/env bash
# マージ待ちの優先度: ボトルネック度 (重み補正つきの時間割合) × 確信度、待ちすぎは先頭
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export STATE=$t
mkdir -p "$t/analysis/b2/h1"
printf '%s\n' '{"id":"b1","pass":true,"score":10}' '{"id":"b2","pass":true,"score":20}' '{"id":"b3","pass":false,"score":0}' >"$t/bench.jsonl"
# GET / が 60% (重み1)、GET /img が 40% (重み0)。クエリ comments は 30s = 全リクエスト時間の 30%
cat >"$t/analysis/b2/h1/endpoints.json" <<'J'
[{"method":"GET","uri":"/","sum":60,"weight":1},{"method":"GET","uri":"/img","sum":40,"weight":0}]
J
cat >"$t/analysis/b2/h1/queries.json" <<'J'
[{"fingerprint":"SELECT * FROM `comments` WHERE `post_id` = ?","sum":30},{"fingerprint":"SELECT * FROM users","sum":10}]
J
q=$root/bin/queue.sh
$q add '{"task_id":"a","title":"index","expected_gain":"high","targets":[{"method":"GET","uri":"/"}]}' >/dev/null   # 0.6 × 1
$q add '{"task_id":"b","title":"img","expected_gain":"high","targets":[{"uri":"/img"}]}' >/dev/null                   # 0.4×0.3=0.12 × 1
$q add '{"task_id":"c","title":"comments","expected_gain":"mid","predicted":20,"targets":[{"query":"from `comments`"}]}' >/dev/null # 0.3 × (0.6+1)/2=0.8 → 0.24
$q add '{"task_id":"d","title":"none","expected_gain":"low"}' >/dev/null                                              # 0.3 × 0.3
out=$($q rank)
echo "$out" | head -1 | grep -q '基準ベンチ: b2' || { echo "FAIL base bench: $out"; exit 1; }
got=$(jq -c '[.queue[] | [.task_id, .priority]]' "$t/queue-rank.json")
[ "$got" = '[["a",0.6],["c",0.24],["b",0.12],["d",0.09]]' ] || { echo "FAIL rank: $got"; exit 1; }
[ "$(jq -c .batch "$t/queue-rank.json")" = '["a"]' ] || { echo "FAIL batch (head not batchable)"; exit 1; }
# まとめて適用: 先頭が batchable なら、batchable・restart なし・area 重複なしを最大 BATCH_MAX 件
cp "$t/merge-queue.json" "$t/q.bak"
jq 'map(.batchable = true | .area = .task_id) | map(if .task_id == "b" then .restart_risk = true elif .task_id == "d" then .area = "a" else . end)' "$t/q.bak" >"$t/merge-queue.json"
$q rank >/dev/null
[ "$(jq -c .batch "$t/queue-rank.json")" = '["a","c"]' ] || { echo "FAIL batch: $(jq -c .batch "$t/queue-rank.json")"; exit 1; }
jq 'map(.batchable = true | .area = .task_id)' "$t/q.bak" >"$t/merge-queue.json"
BATCH_MAX=2 $q rank >/dev/null
[ "$(jq -c .batch "$t/queue-rank.json")" = '["a","c"]' ] || { echo "FAIL batch max"; exit 1; }
cp "$t/q.bak" "$t/merge-queue.json"
# 待ちすぎ: d を 30 分前に積んだことにすると先頭
jq 'map(if .task_id == "d" then .ready_at -= 1800 else . end)' "$t/merge-queue.json" >"$t/x" && mv "$t/x" "$t/merge-queue.json"
$q rank >/dev/null
[ "$(jq -r '.queue[0].task_id' "$t/queue-rank.json")" = d ] || { echo "FAIL aging"; exit 1; }
# pop・同じ task の add は置き換え
$q pop a; $q add '{"task_id":"c","title":"comments v2","expected_gain":"low"}'
[ "$(jq -c 'map(.task_id)' "$t/merge-queue.json")" = '["b","d","c"]' ] || { echo "FAIL pop/add"; exit 1; }
# ベンチが無いときも落ちない
rm "$t/bench.jsonl"; $q rank >/dev/null
[ "$(jq -r '.queue | length' "$t/queue-rank.json")" = 3 ] || { echo "FAIL no bench"; exit 1; }
echo ok
