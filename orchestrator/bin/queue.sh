#!/usr/bin/env bash
# マージ待ちの列 ($STATE/merge-queue.json)。Coordinator が Implementer の完了を積み、ベンチの枠が空いたら rank の先頭から1つ処理する。
# usage:
#   bin/queue.sh add '<json>'   {task_id, branch, title, area, expected_gain, restart_risk, batchable, targets:[{method,uri}|{query}]} を積む (ready_at は今)
#   bin/queue.sh rank           優先度順に並べ、$STATE/queue-rank.json に書いて表を出す。.batch が次のベンチでまとめて適用する task_id
#   bin/queue.sh pop <task_id>  列から外す (マージした・リベース依頼した・取り下げた)
# 優先度 = ボトルネック度 × 確信度 (どちらも 0〜1)
#   ボトルネック度: 最新の pass ベンチで targets が占める時間の割合の最大値
#     endpoint {method, uri}: 全エンドポイントの合計時間に対する割合 × 採点の重みの補正 (weight>0: 1, 0: 0.3, 未記載: 0.6)
#     query {query}: fingerprint にその文字列を含む (大小無視) クエリの合計時間の、全エンドポイントの合計時間に対する割合
#       (エンドポイントと同じ分母にして比べられるようにする。エンドポイントのデータが無ければ全クエリ時間で割る)
#     targets が無い・データが無いときは 0.3
#   確信度: expected_gain (high 1 / mid 0.6 / low 0.3)。ローカル予測 (predicted) は使わない
#     (リハ#2: 負荷が固定のローカルベンチでは予測の大半が ±1% に固まり符号も外れた。predicted は台帳に参考値として残る)
#   AGE_MIN 分 (既定 20) 以上待ったものは優先度に関係なく先頭へ (古い順)
# まとめて適用 (.batch): 先頭が batchable かつ restart_risk でなければ、同じ条件で area が重ならないものを
#   順位順に BATCH_MAX 件 (既定 3) まで足す。先頭が batchable でなければ先頭だけ (効果を単独で測る)
set -euo pipefail
cd "$(dirname "$0")/.."
STATE=${STATE:-state}
q=$STATE/merge-queue.json
[ -f "$q" ] || echo '[]' >"$q"
now=$(date +%s)

case ${1:-} in
  add)
    jq --argjson e "$2" --argjson now "$now" 'map(select(.task_id != $e.task_id)) + [$e + {ready_at: $now}]' "$q" >"$q.tmp" && mv "$q.tmp" "$q" ;;
  pop)
    jq --arg id "$2" 'map(select(.task_id != $id))' "$q" >"$q.tmp" && mv "$q.tmp" "$q" ;;
  rank)
    # 最新の pass かつ score>0 のベンチ
    id=$( { jq -r 'select(.pass and .score > 0) | .id' "$STATE/bench.jsonl" 2>/dev/null || true; } | tail -n1)
    d=$STATE/analysis/$id
    ep=$( [ -n "$id" ] && cat "$d"/*/endpoints.json 2>/dev/null | jq -s 'add // []' || echo '[]')
    qs=$( [ -n "$id" ] && cat "$d"/*/queries.json 2>/dev/null | jq -s 'add // []' || echo '[]')
    jq --argjson ep "$ep" --argjson qs "$qs" --argjson now "$now" --argjson age "${AGE_MIN:-20}" --argjson max "${BATCH_MAX:-3}" --arg bench "$id" '
      ($ep | map(.sum) | add // 0) as $et | ($qs | map(.sum) | add // 0) as $qt
      | def wf: if . == null then 0.6 elif . > 0 then 1 else 0.3 end;
        def eshare($t): [$ep[] | select(($t.method // "*") as $m | ($m == "*" or $m == .method) and .uri == $t.uri)]
          | if $et > 0 then (map(.sum * (.weight | wf)) | add // 0) / $et else 0 end;
        def qshare($t): ($t.query | ascii_downcase) as $s | [$qs[] | select(.fingerprint | ascii_downcase | contains($s))]
          | (if $et > 0 then $et else $qt end) as $den | if $den > 0 then (map(.sum) | add // 0) / $den else 0 end;
        def r2: . * 100 | round / 100;
      map(
        ([(.targets // [])[] | if .query then qshare(.) else eshare(.) end] | max // null) as $deg
        | ({"high": 1, "mid": 0.6, "low": 0.3}[.expected_gain // ""] // 0.5) as $g
        | $g as $conf
        | (if $deg == null or ($et == 0 and $qt == 0) then 0.3 else $deg end) as $degree
        | ((($now - .ready_at) / 60) | floor) as $wait
        | . + {degree: ($degree | r2), confidence: ($conf | r2), priority: ($degree * $conf | r2), wait_min: $wait, aged: ($wait >= $age)})
      | (map(select(.aged)) | sort_by(.ready_at)) + (map(select(.aged | not)) | sort_by(-.priority))
      | def ok: (.batchable == true) and (.restart_risk != true);
        (if length == 0 then [] elif (.[0] | ok) then
          reduce .[1:][] as $e ([.[0]]; if length < $max and ($e | ok) and ([.[].area] | index($e.area) | not) then . + [$e] else . end)
        else [.[0]] end | map(.task_id)) as $batch
      | {bench: $bench, ranked_at: $now, batch: $batch, queue: .}' "$q" >"$STATE/queue-rank.json"
    jq -r '"基準ベンチ: \(.bench // "なし")", "次にまとめて適用: \(.batch | join(", "))", "順位 優先度 (度×確信) 待ち分 task title",
      (.queue | to_entries[] | "\(.key + 1) \(.value.priority) (\(.value.degree)×\(.value.confidence)) \(.value.wait_min)\(if .value.aged then "*" else "" end) \(.value.task_id) \(.value.title)")' "$STATE/queue-rank.json" ;;
  *) sed -n '2,6p' "$0" >&2; exit 2 ;;
esac
