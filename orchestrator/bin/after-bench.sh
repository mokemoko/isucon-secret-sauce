#!/usr/bin/env bash
# usage: bin/after-bench.sh <bench_id>   ベンチの後に Coordinator がまとめて確かめることを1回で出す。競技リポジトリの中で実行する (列の競合を git で見るため)
#   1. 採否の判定 (bin/judge.sh。verdicts.jsonl に残る)
#   2. 警告・エラー: analysis/<id>/warnings.txt の行数を、前回の pass ベンチと比べる (warnings_increased=yes なら LocalBench の改善を起動する)
#   3. ボトルネックの移動: 前回の pass ベンチと、重みのあるエンドポイント (重みが無ければ全体)・クエリ・CPU を最も使うプロセスの
#      それぞれ1位を比べる (moved=yes なら summary.md を読み、insights を書き換え、Analyst の起動を考える)
#   4. 再起動確認の要否: $STATE/restart-pending.tsv (task_id <TAB> マージコミット <TAB> 採用時刻 epoch) が3件以上か、最古が45分以上前
#   5. マージ待ちの列: git fetch してから bin/queue.sh rank (main と競合するものは ! と「リベースを頼む」行に出る)
# どれかが失敗しても残りは続ける (失敗は ERR 行に出す)
set -uo pipefail
caller=$PWD
cd "$(dirname "$0")/.."
orc=$PWD
STATE=${STATE:-state}
id=${1:?usage: after-bench.sh <bench_id>}
a=$STATE/analysis

echo "## judge"
bin/judge.sh "$id" || echo "ERR judge.sh が失敗"

# 前回の pass ベンチ (このベンチより前で pass かつ score>0 の最後)
prev=$(jq -rs --arg id "$id" '(map(.id) | index($id)) as $i | if $i == null then empty else .[:$i] | map(select(.pass and .score > 0)) | last | .id // empty end' "$STATE/bench.jsonl" 2>/dev/null)
echo; echo "## 前回の pass ベンチ: ${prev:-なし}"

echo; echo "## warnings"
wc_of() { [ -f "$a/$1/warnings.txt" ] && wc -l <"$a/$1/warnings.txt" | tr -d ' '; }
cur_w=$(wc_of "$id"); prev_w=$( [ -n "$prev" ] && wc_of "$prev")
if [ -z "$cur_w" ]; then echo "warnings=不明 (warnings.txt が無い)"
else
  inc=no; [ -n "$prev_w" ] && [ "$cur_w" -gt "$prev_w" ] && inc=yes
  echo "warnings=$cur_w (前回 ${prev_w:-不明}) warnings_increased=$inc"
  [ "$inc" = yes ] && head -n3 "$a/$id/warnings.txt" | cut -c1-200
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
