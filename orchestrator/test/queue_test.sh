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
$q add '{"task_id":"c","title":"comments","expected_gain":"mid","targets":[{"query":"from `comments`"}]}' >/dev/null # 0.3 × 0.6 = 0.18
$q add '{"task_id":"d","title":"none","expected_gain":"low"}' >/dev/null                                              # 0.3 × 0.3
out=$($q rank)
echo "$out" | head -1 | grep -q '基準ベンチ: b2' || { echo "FAIL base bench: $out"; exit 1; }
got=$(jq -c '[.queue[] | [.task_id, .priority]]' "$t/queue-rank.json")
[ "$got" = '[["a",0.6],["c",0.18],["b",0.12],["d",0.09]]' ] || { echo "FAIL rank: $got"; exit 1; }
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
# degree_hint: 実測より大きければ使う (e は targets の時間占有 0 だが hint 0.8 × high)。小さければ実測のまま
$q add '{"task_id":"e","title":"internal","expected_gain":"high","targets":[{"method":"GET","uri":"/none"}],"degree_hint":0.8}' >/dev/null
$q add '{"task_id":"f","title":"small hint","expected_gain":"high","targets":[{"method":"GET","uri":"/"}],"degree_hint":0.1}' >/dev/null
out=$($q rank)
[ "$(jq -c '[.queue[] | select(.task_id == "e" or .task_id == "f") | [.task_id, .priority, .degree_src]]' "$t/queue-rank.json")" = '[["e",0.8,"hint"],["f",0.6,"measured"]]' ] \
  || { echo "FAIL degree_hint: $(jq -c .queue "$t/queue-rank.json")"; exit 1; }
echo "$out" | grep -q '0.8 (0.8h×1)' || { echo "FAIL hint mark: $out"; exit 1; }
$q pop e; $q pop f
# requeue: task_id と branch を付け替え、ready_at は引き継ぐ
r0=$(jq -r '.[] | select(.task_id == "d") | .ready_at' "$t/merge-queue.json")
$q requeue d d2 impl/d
[ "$(jq -c '.[] | select(.task_id == "d2") | [.ready_at, .branch]' "$t/merge-queue.json")" = "[$r0,\"impl/d\"]" ] || { echo "FAIL requeue"; exit 1; }
$q requeue d2 d
# 競合: 呼び出し元の git repo で origin/main と merge-tree。競合するものは ! を付けて .batch から外し、次のものから組む
g=$t/git; git init -q --bare "$g/origin.git"; git init -q -b main "$g/w"
( cd "$g/w" && git config user.email t@t && git config user.name t && echo base >f && git add f && git commit -qm base \
  && git remote add origin "$g/origin.git" && git push -q origin main \
  && git switch -qc impl/x && echo x >f && git commit -qam x && git push -q origin impl/x \
  && git switch -q main && git switch -qc impl/y && echo y >g && git add g && git commit -qm y && git push -q origin impl/y \
  && git switch -q main && echo main >f && git commit -qam main && git push -q origin main && git fetch -q origin )
cp "$t/merge-queue.json" "$t/q2.bak"
echo '[{"task_id":"x","branch":"impl/x","title":"conflicting","expected_gain":"high","batchable":true,"area":"x","ready_at":0},
       {"task_id":"y","branch":"impl/y","title":"clean","expected_gain":"low","batchable":true,"area":"y","ready_at":0}]' \
  | jq --argjson now "$(date +%s)" 'map(.ready_at = $now)' >"$t/merge-queue.json"
out=$(cd "$g/w" && $q rank)
[ "$(jq -c '[.batch, .conflicts, [.queue[] | .conflict]]' "$t/queue-rank.json")" = '[["y"],["x"],[true,false]]' ] \
  || { echo "FAIL conflict: $(jq -c . "$t/queue-rank.json")"; exit 1; }
echo "$out" | grep -q 'main と競合 (リベースを頼む): x' || { echo "FAIL conflict line: $out"; exit 1; }
cp "$t/q2.bak" "$t/merge-queue.json"
# 最新の pass ベンチに解析結果が無い (計測を止めた後) ときも落ちない
echo '{"id":"b4","pass":true,"score":30}' >>"$t/bench.jsonl"; $q rank >/dev/null || { echo "FAIL no analysis"; exit 1; }
# ベンチが無いときも落ちない
rm "$t/bench.jsonl"; $q rank >/dev/null
[ "$(jq -r '.queue | length' "$t/queue-rank.json")" = 3 ] || { echo "FAIL no bench"; exit 1; }
# 0点の間: [0点解消] が優先度・待ち時間に関係なく先頭、繰り上げ (*) なし
cp "$t/merge-queue.json" "$t/zq.bak"; cp "$t/bench.jsonl" "$t/zb.bak" 2>/dev/null || :
old=$(( $(date +%s) - 3600 ))
printf '%s\n' "[{\"task_id\":\"old\",\"title\":\"小さい変更\",\"area\":\"a\",\"expected_gain\":\"high\",\"degree_hint\":0.9,\"ready_at\":$old},{\"task_id\":\"fix\",\"title\":\"[0点解消] デッドロック\",\"area\":\"b\",\"expected_gain\":\"low\",\"ready_at\":$(date +%s)}]" >"$t/merge-queue.json"
echo '{"id":"z1","pass":true,"score":0}' >"$t/bench.jsonl"
out=$($q rank)
[ "$(jq -r '.queue[0].task_id + " " + (.queue[0].aged|tostring) + " " + (.queue[1].aged|tostring) + " " + (.zero|tostring)' "$t/queue-rank.json")" = "fix false false true" ] \
  && echo "$out" | grep -q '0点の間' || { echo "FAIL zero: $(jq -c '.queue|map(.task_id)' "$t/queue-rank.json")"; exit 1; }
# pass に戻れば繰り上げが効く
echo '{"id":"z2","pass":true,"score":50}' >>"$t/bench.jsonl"; $q rank >/dev/null
[ "$(jq -r '.queue[0].task_id' "$t/queue-rank.json")" = old ] || { echo "FAIL zero off"; exit 1; }
cp "$t/zq.bak" "$t/merge-queue.json"; cp "$t/zb.bak" "$t/bench.jsonl" 2>/dev/null || rm -f "$t/bench.jsonl"
# 人の PR (pr のある項目) は、待ちすぎのものよりも先頭 (古い順)。まとめて適用しない
cp "$t/merge-queue.json" "$t/pq.bak"
old=$(( $(date +%s) - 3600 ))
printf '%s\n' "[{\"task_id\":\"aged\",\"title\":\"a\",\"area\":\"a\",\"expected_gain\":\"high\",\"batchable\":true,\"ready_at\":$old},{\"task_id\":\"pr-7\",\"pr\":7,\"title\":\"PR#7 x\",\"area\":\"b\",\"expected_gain\":\"mid\",\"batchable\":false,\"ready_at\":$(date +%s)}]" >"$t/merge-queue.json"
$q rank >/dev/null
[ "$(jq -c '[[.queue[].task_id], .batch]' "$t/queue-rank.json")" = '[["pr-7","aged"],["pr-7"]]' ] || { echo "FAIL pr first: $(jq -c . "$t/queue-rank.json")"; exit 1; }
cp "$t/pq.bak" "$t/merge-queue.json"
# add・pop・requeue は queue.log に (時刻, 操作, 列の長さ) を残す。rank は残さない
n=$(wc -l <"$t/queue.log" | tr -d ' '); $q pop nonexistent; $q rank >/dev/null
[ "$(wc -l <"$t/queue.log" | tr -d ' ')" = $((n + 1)) ] && tail -n1 "$t/queue.log" | grep -qE '^[0-9]+	pop	3$' || { echo "FAIL queue.log"; tail -3 "$t/queue.log"; exit 1; }
echo ok
