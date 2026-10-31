#!/usr/bin/env bash
# usage: bin/after-bench.sh <bench_id>   ベンチの後に Coordinator がまとめて確かめることを1回で出す。競技リポジトリの中で実行する (列の競合を git で見るため)
#   1. 採否の判定 (bin/judge.sh。verdicts.jsonl に残る)
#   2. 警告・エラー: analysis/<id>/penalty.txt (ベンチが出す減点の件数。env.sh の BENCH_PENALTY_RE) があればその値を、無ければ warnings.txt の行数を、
#      前回の pass ベンチと比べる (warnings_increased=yes なら LocalBench の改善を起動する)
#   3. ボトルネックの移動: 前回の pass ベンチと、重みのあるエンドポイント (重みが無ければ全体)・クエリ・CPU を最も使うプロセスの
#      それぞれ1位を比べる (moved=yes なら summary.md を読み、insights を書き換え、Analyst の起動を考える)
#   4. 再起動確認の要否: $STATE/restart-pending.tsv (task_id <TAB> マージコミット <TAB> 採用時刻 epoch) が3件以上か、最古が45分以上前
#   5. マージ待ちの列: git fetch してから bin/queue.sh rank (main と競合するものは ! と「リベースを頼む」行に出る)
#   6. 承認待ちの仮説: タイトルが [要承認] で始まる未着手のタスク (pending・ready) のうち、ゲートが無いもの (「ゲート未作成」) と、
#      ゲートが解決済みなのに未着手のもの (「回答済み・未着手」)。ゲートはそのタスクに付けるか、質問文にその task_id を書く
#   7. 人の PR: このベンチで測った PR に判定を、列で main と競合した PR にリベースの依頼を、bin/team.sh comment で書く
#   8. main への列を通らない変更: 直前のベンチからの main の first-parent に、Coordinator のマージ・revert 以外があれば出す
# どれかが失敗しても残りは続ける (失敗は ERR 行に出す)
set -uo pipefail
caller=$PWD
cd "$(dirname "$0")/.."
orc=$PWD
STATE=${STATE:-state}; ORCA=${ORCA:-orca}
id=${1:?usage: after-bench.sh <bench_id>}
a=$STATE/analysis

# 判定済みのベンチなら先に知らせる (bench.sh が deploy failed などで台帳に足さずに終わり、最終行の前回のベンチが渡されることがある)
if [ -s "$STATE/verdicts.jsonl" ] && jq -e --arg id "$id" 'select(.id == $id)' "$STATE/verdicts.jsonl" >/dev/null 2>&1; then
  echo "WARN $id は判定済み。直前の bench.sh が失敗して台帳に載らなかったなら、この出力は前回のベンチのもの (bench.sh の出力を確かめ、直してからやり直す)"
  echo
fi

echo "## judge"
jout=$(bin/judge.sh "$id") || jout="ERR judge.sh が失敗"
echo "$jout"

# 前回の pass ベンチ (このベンチより前で pass かつ score>0 の最後)
prev=$(jq -rs --arg id "$id" '(map(.id) | index($id)) as $i | if $i == null then empty else .[:$i] | map(select(.pass and .score > 0)) | last | .id // empty end' "$STATE/bench.jsonl" 2>/dev/null)
echo; echo "## 前回の pass ベンチ: ${prev:-なし}"

echo; echo "## warnings"
wc_of() { [ -f "$a/$1/warnings.txt" ] && wc -l <"$a/$1/warnings.txt" | tr -d ' '; }
pen_of() { [ -f "$a/$1/penalty.txt" ] && tr -dc '0-9' <"$a/$1/penalty.txt"; }
kind=warnings; cur_w=$(pen_of "$id")
if [ -n "$cur_w" ]; then kind=penalty; prev_w=$( [ -n "$prev" ] && pen_of "$prev")
else cur_w=$(wc_of "$id"); prev_w=$( [ -n "$prev" ] && wc_of "$prev"); fi
if [ -z "$cur_w" ]; then echo "warnings=不明 (warnings.txt が無い)"
else
  inc=no; [ -n "$prev_w" ] && [ "$cur_w" -gt "$prev_w" ] && inc=yes
  [ "$kind" = penalty ] && echo "penalty=$cur_w (前回 ${prev_w:-不明}。ベンチが出す減点の件数) warnings_increased=$inc" \
    || echo "warnings=$cur_w (前回 ${prev_w:-不明}) warnings_increased=$inc"
  [ "$inc" = yes ] && head -n3 "$a/$id/warnings.txt" 2>/dev/null | cut -c1-200
fi

# 各ベンチの1位: エンドポイント (method uri)・クエリ (fingerprint の先頭)・プロセス (host:comm)
tops() {
  local d=$a/$1
  local ep q p
  ep=$(cat "$d"/*/endpoints.json 2>/dev/null | jq -rs 'add // [] | (if any(.[]; (.weight // 0) > 0) then map(select((.weight // 0) > 0)) else . end)
    | group_by(.method + " " + .uri) | map({k: (.[0].method + " " + .[0].uri), s: (map(.sum) | add)}) | max_by(.s) | .k // "-"' 2>/dev/null || echo -)
  q=$(cat "$d"/*/queries.json 2>/dev/null | jq -rs 'add // [] | group_by(.fingerprint) | map({k: .[0].fingerprint, s: (map(.sum) | add)}) | max_by(.s) | .k // "-" | .[0:80]' 2>/dev/null || echo -)
  p=$(for f in "$d"/*/resources.json; do [ -f "$f" ] && jq -c --arg h "$(basename "$(dirname "$f")")" '.procs[0] // empty | {k: ($h + ":" + .comm), c: .cpu_avg}' "$f"; done 2>/dev/null \
    | jq -rs 'max_by(.c) | .k // "-"' 2>/dev/null || echo -)
  printf '%s\n%s\n%s\n' "${ep:--}" "${q:--}" "${p:--}"
}
echo; echo "## ボトルネックの移動"
if [ -z "$prev" ] || [ ! -d "$a/$id" ]; then echo "moved=不明 (比べる pass ベンチか解析結果が無い)"
else
  tops "$id" >"$a/$id/tops.txt"; tops "$prev" >"$a/$id/tops.prev.txt"
  moved=no; out=""
  for k in 1 2 3; do
    name=$(echo "endpoint query process" | cut -d' ' -f$k)
    c=$(sed -n "${k}p" "$a/$id/tops.txt"); o=$(sed -n "${k}p" "$a/$id/tops.prev.txt")
    if [ "$c" != "$o" ] && [ "$c" != - ] && [ "$o" != - ]; then moved=yes; out="$out$name: $o -> $c"$'\n'
    else out="$out$name: $c (変わらず)"$'\n'; fi
  done
  rm -f "$a/$id/tops.txt" "$a/$id/tops.prev.txt"
  echo "moved=$moved"; printf '%s' "$out"
fi

echo; echo "## 再起動確認"
pf=$STATE/restart-pending.tsv
n=0; [ -s "$pf" ] && n=$(grep -c . "$pf")
if [ "$n" -gt 0 ]; then
  oldest=$(cut -f3 "$pf" | grep -E '^[0-9]+$' | sort -n | head -n1)
  age=$( [ -n "$oldest" ] && echo $(( ($(date +%s) - oldest) / 60 )) || echo "?")
  due=no; { [ "$n" -ge 3 ] || { [ "$age" != "?" ] && [ "$age" -ge 45 ]; }; } && due=yes
  echo "pending=$n 最古=${age}分前 restart_check_due=$due ($(cut -f1 "$pf" | paste -sd, -))"
else echo "pending=0 restart_check_due=no"; fi

echo; echo "## マージ待ちの列"
git -C "$caller" fetch -q origin 2>/dev/null || echo "ERR git fetch に失敗 (競合の確認は古い origin で行う)"
(cd "$caller" && "$orc/bin/queue.sh" rank) || echo "ERR queue.sh rank が失敗"

# 7. 人の PR (task が pr-<番号>): このベンチの判定と、列で main と競合したことを PR にコメントする (競合は同じ組み合わせで1回だけ)
echo; echo "## 人の PR"
row=$(jq -c --arg id "$id" 'select(.id == $id)' "$STATE/bench.jsonl" 2>/dev/null | tail -n1)
sha=$(echo "$row" | jq -r '.sha // ""' 2>/dev/null)
v=$(echo "$jout" | sed -n 's/^verdict=\([a-z]*\).*/\1/p')
case $v in
  adopt) what="採用 (main に入ったまま)" ;; retry) what="基準を割った1回目。同じ版をもう1回測る" ;;
  revert) what="2回続けて (終盤は high 以外1回目で) 基準を割ったので revert する。直して push し、queue ラベルを付け直せばもう一度測る" ;;
  human) what="fail か0点。人間の判断待ち" ;; *) what="判定できなかった" ;;
esac
n_pr=0
for t in $(echo "$row" | jq -r '.task // "" | split(",")[] | select(startswith("pr-"))' 2>/dev/null); do
  n_pr=$((n_pr + 1))
  "$orc/bin/team.sh" comment "$t" "ベンチ $id (${sha:0:7}): $what
\`$jout\`" && echo "判定をコメント: $t $v" || echo "ERR $t にコメントできない"
done
for t in $(jq -r '.conflicts[]? | select(startswith("pr-"))' "$STATE/queue-rank.json" 2>/dev/null); do
  n_pr=$((n_pr + 1))
  br=$(jq -r --arg t "$t" '.queue[] | select(.task_id == $t) | .branch' "$STATE/queue-rank.json")
  m=$(git -C "$caller" rev-parse -q --verify origin/main 2>/dev/null)
  key="$t $(git -C "$caller" rev-parse -q --verify "origin/$br" 2>/dev/null) $m"
  if grep -qxF "$key" "$STATE/pr-notified" 2>/dev/null; then echo "main と競合 (通知済み): $t"; continue; fi
  "$orc/bin/team.sh" comment "$t" "main (${m:0:7}) と競合しています。リベースして push してください。列には残っているので、ラベルの付け直しは不要です" \
    && echo "$key" >>"$STATE/pr-notified" && echo "main と競合を通知: $t (ワーカーにリベースを頼まない)" || echo "ERR $t にコメントできない"
done
[ "$n_pr" = 0 ] && echo "なし"

# 8. main への列を通らない変更: 直前のベンチの sha からこのベンチの sha までの first-parent のうち、マージでも revert でもないコミット
#    (人が main に直接 push したもの) と、GitHub の画面でマージしたもの (Merge pull request #...)。Coordinator のマージは
#    メッセージが一定しない (Merge <task_id> <title> など) ので、マージコミットか、その cherry-pick (件名が Merge で始まる) を列のものとみなす
echo; echo "## main への列を通らない変更"
psha=$(jq -rs --arg id "$id" '(map(.id) | index($id)) as $i | if $i == null or $i == 0 then empty else .[$i - 1].sha // empty end' "$STATE/bench.jsonl" 2>/dev/null)
if [ -z "$psha" ] || [ -z "$sha" ] || ! git -C "$caller" cat-file -e "$psha^{commit}" 2>/dev/null || ! git -C "$caller" cat-file -e "$sha^{commit}" 2>/dev/null; then
  echo "不明 (直前のベンチか、その sha が無い)"
else
  out=$(git -C "$caller" log --first-parent --format='%s%x09%h %an' "$psha..$sha" \
    | awk -F'\t' '$1 ~ /^Merge pull request #/ || ($1 !~ /^Merge / && $1 !~ /^Revert /) { print $2 ": " $1 }')
  if [ -z "$out" ]; then echo "なし"
  else
    echo "あり (このベンチの採否はこれを含む。人に、PR に queue ラベルを付けて出すよう頼む)"
    echo "$out"
  fi
fi

echo; echo "## 承認待ちの仮説"
run=$(cat "$STATE/run_id" 2>/dev/null)
if [ -z "$run" ]; then echo "run_id が無い"
else
  tasks=$("$ORCA" orchestration task-list --run "$run" --json 2>/dev/null | jq -c '[.result.tasks[]? | select((.task_title // "") | startswith("[要承認]")) | select(.status == "pending" or .status == "ready") | {id, title: .task_title}]') || tasks=
  gates=$("$ORCA" orchestration gate-list --run "$run" --json 2>/dev/null | jq -c '[.result.gates[]? | {task_id, status, question: (.question // "")}]') || gates=
  if [ -z "$tasks" ] || [ -z "$gates" ]; then echo "ERR task-list か gate-list に失敗"
  else
    jq -rn --argjson t "$tasks" --argjson g "$gates" '
      [$t[] | . as $x | ([$g[] | select(.task_id == $x.id or (.question | contains($x.id)))]) as $mine
        | if ($mine | length) == 0 then "ゲート未作成: \($x.id) \($x.title)  → needs_human のゲートを作る"
          elif ($mine | all(.status != "pending")) then "回答済み・未着手: \($x.id) \($x.title)  → 回答を確かめて着手するか閉じる"
          else empty end] | if length == 0 then "なし" else .[] end'
  fi
fi

