#!/usr/bin/env bash
# マージ待ちの列 ($STATE/merge-queue.json)。Coordinator が Implementer の完了を積み、ベンチの枠が空いたら rank の先頭から1つ処理する。
# usage:
#   bin/queue.sh add '<json>'   {task_id, branch, title, area, expected_gain, restart_risk, batchable, targets:[{method,uri}|{query}], degree_hint} を積む (ready_at は今)
#   bin/queue.sh requeue <古い task_id> <新しい task_id> [branch]  リベースを別タスクで頼んだときに付け替える (ready_at = 待ち時間は引き継ぐ)
#   bin/queue.sh rank           優先度順に並べ、$STATE/queue-rank.json に書いて表を出す。.batch が次のベンチでまとめて適用する task_id
#   bin/queue.sh pop <task_id>  列から外す (マージした・リベース依頼した・取り下げた)
# 優先度 = ボトルネック度 × 確信度 (どちらも 0〜1)
#   ボトルネック度: 最新の pass ベンチで targets が占める時間の割合の最大値
#     endpoint {method, uri}: 全エンドポイントの合計時間に対する割合 × 採点の重みの補正 (weight>0: 1, 0: 0.3, 未記載: 0.6)
#     query {query}: fingerprint にその文字列を含む (大小無視) クエリの合計時間の、全エンドポイントの合計時間に対する割合
#       (エンドポイントと同じ分母にして比べられるようにする。エンドポイントのデータが無ければ全クエリ時間で割る)
#     targets が無い・データが無いときは 0.3
#     degree_hint (任意、0〜1) は Analyst の見積もり。時間占有では測れない効果 (結果に応じた加点に効く内部処理など) を表す。
#       実測より大きければ hint を使い、表に h を付ける
#   確信度: expected_gain (high 1 / mid 0.6 / low 0.3)。ローカルベンチの予測は使わない (負荷が固定で、順位付けに使えなかった。リハ#2)
#   AGE_MIN 分 (既定 20) 以上待ったものは優先度に関係なく先頭へ (古い順)
#   0点の間 (ベースラインから、pass かつ score>0 のベンチがまだ無い): タイトルが [0点解消] のものを先頭に置き、待ち時間の繰り上げはしない (0点の解消を追い越させない)
# 競合: 呼び出し元のディレクトリが git repo なら、各 branch を origin/<branch> と origin/main で git merge-tree し、競合するものに
#   conflict=true を付ける (表に ! を付ける)。競合するものは .batch に入れず、先頭が競合なら次のものから組む。fetch は呼び出し側で済ませる
# まとめて適用 (.batch): 先頭が batchable かつ restart_risk でなければ、同じ条件で area が重ならないものを
#   順位順に BATCH_MAX 件 (既定 3) まで足す。先頭が batchable でなければ先頭だけ (効果を単独で測る)
set -euo pipefail
caller=$PWD
cd "$(dirname "$0")/.."
STATE=${STATE:-state}
q=$STATE/merge-queue.json
[ -f "$q" ] || echo '[]' >"$q"
now=$(date +%s)
# 列の長さの推移を $STATE/queue.log (epoch <TAB> 操作 <TAB> 列の長さ) に残す。ベンチ枠の稼働率を「列に待ちがあった時間」で評価するため
qlog() { printf '%s\t%s\t%s\n' "$now" "$1" "$(jq length "$q")" >>"$STATE/queue.log"; }

case ${1:-} in
  add)
    jq --argjson e "$2" --argjson now "$now" 'map(select(.task_id != $e.task_id)) + [$e + {ready_at: $now}]' "$q" >"$q.tmp" && mv "$q.tmp" "$q" && qlog "$1" ;;
  requeue)
    jq --arg o "$2" --arg n "$3" --arg b "${4:-}" 'map(if .task_id == $o then .task_id = $n | (if $b != "" then .branch = $b else . end) else . end)' "$q" >"$q.tmp" && mv "$q.tmp" "$q" && qlog "$1" ;;
  pop)
    jq --arg id "$2" 'map(select(.task_id != $id))' "$q" >"$q.tmp" && mv "$q.tmp" "$q" && qlog "$1" ;;
  rank)
    # 最新の pass かつ score>0 のベンチ
    id=$( { jq -r 'select(.pass and .score > 0) | .id' "$STATE/bench.jsonl" 2>/dev/null || true; } | tail -n1)
    d=$STATE/analysis/$id
    zero=false; [ -z "$id" ] && [ -s "$STATE/bench.jsonl" ] && zero=true   # ベースラインから0点が続いている (pass かつ score>0 がまだ無い)
    # 解析結果が無い (計測を止めた後など) ときは空。cat の失敗で '[]' が2回出ないよう、失敗は握りつぶしてから jq に渡す
    ep=$( { [ -n "$id" ] && cat "$d"/*/endpoints.json 2>/dev/null || true; } | jq -s 'add // []')
    qs=$( { [ -n "$id" ] && cat "$d"/*/queries.json 2>/dev/null || true; } | jq -s 'add // []')
    # 競合の確認 (merge-tree の終了コード 1 = 競合。ブランチが無いなどのエラーは null)
    cf='{}'
    if git -C "$caller" rev-parse --verify -q origin/main >/dev/null 2>&1; then
      while IFS=$'\t' read -r tid br; do
        [ -n "$br" ] || continue
        rc=0; git -C "$caller" merge-tree --write-tree origin/main "origin/$br" >/dev/null 2>&1 || rc=$?
        case $rc in 0) v=false ;; 1) v=true ;; *) v=null ;; esac
        cf=$(echo "$cf" | jq --arg k "$tid" --argjson v "$v" '. + {($k): $v}')
      done < <(jq -r '.[] | select(.reapply == null) | [.task_id, (.branch // "")] | @tsv' "$q")
    fi
    jq --argjson cf "$cf" --argjson ep "$ep" --argjson qs "$qs" --argjson now "$now" --argjson age "${AGE_MIN:-20}" --argjson max "${BATCH_MAX:-3}" --arg bench "$id" --argjson zero "$zero" '
      ($ep | map(.sum) | add // 0) as $et | ($qs | map(.sum) | add // 0) as $qt
      | def wf: if . == null then 0.6 elif . > 0 then 1 else 0.3 end;
        def eshare($t): [$ep[] | select(($t.method // "*") as $m | ($m == "*" or $m == .method) and .uri == $t.uri)]
          | if $et > 0 then (map(.sum * (.weight | wf)) | add // 0) / $et else 0 end;
        def qshare($t): ($t.query | ascii_downcase) as $s | [$qs[] | select(.fingerprint | ascii_downcase | contains($s))]
          | (if $et > 0 then $et else $qt end) as $den | if $den > 0 then (map(.sum) | add // 0) / $den else 0 end;
        def r2: . * 100 | round / 100;
      map(
        ([(.targets // [])[] | if .query then qshare(.) else eshare(.) end] | max // null) as $deg
        | ({"high": 1, "mid": 0.6, "low": 0.3}[.expected_gain // ""] // 0.5) as $conf
        | (if $deg == null or ($et == 0 and $qt == 0) then 0.3 else $deg end) as $measured
        | ((.degree_hint // 0) > $measured) as $hinted
        | (if $hinted then .degree_hint else $measured end) as $degree
        | ((($now - .ready_at) / 60) | floor) as $wait
        | . + {conflict: $cf[.task_id], degree: ($degree | r2), degree_src: (if $hinted then "hint" else "measured" end), confidence: ($conf | r2), priority: ($degree * $conf | r2), wait_min: $wait, aged: ($wait >= $age and ($zero | not))})
      | if $zero then (map(select((.title // "") | startswith("[0点解消]"))) | sort_by(-.priority)) + (map(select((.title // "") | startswith("[0点解消]") | not)) | sort_by(-.priority))
        else (map(select(.aged)) | sort_by(.ready_at)) + (map(select(.aged | not)) | sort_by(-.priority)) end
      | def ok: (.batchable == true) and (.restart_risk != true);
        map(select(.conflict != true)) as $mergeable
        | ($mergeable | if length == 0 then [] elif (.[0] | ok) then
          reduce .[1:][] as $e ([.[0]]; if length < $max and ($e | ok) and ([.[].area] | index($e.area) | not) then . + [$e] else . end)
        else [.[0]] end | map(.task_id)) as $batch
      | {bench: $bench, ranked_at: $now, zero: $zero, batch: $batch, conflicts: map(select(.conflict == true) | .task_id), queue: .}' "$q" >"$STATE/queue-rank.json"
    jq -r '"基準ベンチ: \(.bench // "なし")\(if .zero then " (0点の間: [0点解消] を先頭に、待ち時間の繰り上げなし)" else "" end)", "次にまとめて適用: \(.batch | join(", "))",
      (if (.conflicts | length) > 0 then "main と競合 (リベースを頼む): \(.conflicts | join(", "))" else empty end),
      "順位 優先度 (度×確信) 待ち分 task title (! は main と競合)",
      (.queue | to_entries[] | "\(.key + 1) \(.value.priority) (\(.value.degree)\(if .value.degree_src == "hint" then "h" else "" end)×\(.value.confidence)) \(.value.wait_min)\(if .value.aged then "*" else "" end)\(if .value.conflict == true then " !" else "" end) \(.value.task_id) \(.value.title)")' "$STATE/queue-rank.json" ;;
  *) sed -n '2,6p' "$0" >&2; exit 2 ;;
esac
