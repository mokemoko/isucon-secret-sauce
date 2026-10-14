#!/usr/bin/env bash
# usage: bin/judge.sh <bench_id>   ベンチ1回の採否を判定し、$STATE/verdicts.jsonl に {id, verdict, ref, noise, threshold} を足して1行で出す
# verdict:
#   human  : fail か score 0。自動で決めない (人間が判断する)
#   adopt  : score >= 基準 × (1 − ノイズ幅)
#   retry  : 基準を割った1回目。同じ sha をもう1回測る (SKIP_DEPLOY=1 bin/bench.sh HEAD "retry <title>")
#   revert : 同じ sha で2回続けて基準を割った
# 基準: このベンチより前の pass・score>0 のうち、revert と判定した sha・このベンチと同じ sha のものを除いた直近3回の中央値
#   (最高点を使うと、たまたま高く出た1回に引きずられて効く変更を落とす。リハ#2)
# ノイズ幅: 同じ sha を続けて測った組 (再起動確認・retry・ベースライン) の相対差 |a−b|/max の直近5組の中央値を [0.05, 0.3] に収める。
#   組が無ければ $STATE/noise (ベースライン2回の差)、それも無ければ 0.1
set -euo pipefail
cd "$(dirname "$0")/.."
STATE=${STATE:-state}
id=${1:?usage: judge.sh <bench_id>}
v=$STATE/verdicts.jsonl; touch "$v"
fallback=$(cat "$STATE/noise" 2>/dev/null || echo 0.1)
out=$(jq -sc --arg id "$id" --slurpfile vs "$v" --argjson fb "$fallback" '
  def median: sort | if length == 0 then null else .[(length - 1) / 2 | floor] end;
  ($vs | map(select(.id != $id) | {(.id): .verdict}) | add // {}) as $vd
  | (map(.id) | index($id)) as $i
  | if $i == null then error("bench \($id) が bench.jsonl に無い") else . end
  | .[$i] as $t | .[:$i] as $prev
  | [$prev[] | select($vd[.id] == "revert") | .sha] as $bad
  | ([$prev[] | select(.pass and .score > 0 and .sha != $t.sha and (.sha as $s | $bad | index($s) | not)) | .score] | .[-3:] | median) as $ref
  | ([range(1; length) as $k | [.[$k - 1], .[$k]] | select(.[0].sha == .[1].sha and all(.[]; .pass and .score > 0))
      | (.[0].score - .[1].score | fabs) / ([.[0].score, .[1].score] | max)] | .[-5:] | median) as $pn
  | ([[($pn // $fb), 0.05] | max, 0.3] | min) as $noise
  | (if $ref == null then null else ($ref * (1 - $noise) | floor) end) as $th
  | ([$prev[] | select(.sha == $t.sha) | $vd[.id]] | index("retry") != null) as $retried
  | {id: $id, score: $t.score, ref: $ref, noise: ($noise * 1000 | round / 1000), threshold: $th,
     verdict: (if ($t.pass | not) or $t.score == 0 then "human"
               elif $th == null or $t.score >= $th then "adopt"
               elif $retried then "revert" else "retry" end)}' "$STATE/bench.jsonl")
{ jq -c --arg id "$id" 'select(.id != $id)' "$v"; echo "$out"; } >"$v.tmp" && mv "$v.tmp" "$v"   # 同じベンチの判定し直しは置き換え
echo "$out" | jq -r '"verdict=\(.verdict) score=\(.score) ref=\(.ref) noise=\(.noise) threshold=\(.threshold)"'
