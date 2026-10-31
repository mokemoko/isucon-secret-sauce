#!/usr/bin/env bash
# オーケストレータの外で作業する人との約束を、競技リポジトリ (env.sh の GH_REPO。private) の GitHub に置く
#   Issue: 作業の宣言。誰でも着手前に立て、本文に「範囲: <触るエンドポイント・テーブル・設定>」を書く。オーケストレータのものは orchestrator ラベル
#   PR + queue ラベル: main に入れたい変更。Coordinator が列に積み (ラベルを queued に替える)、ベンチ・採否を経てマージする
#   main に直接 push しない (列を通らない変更は、次のベンチの採否を取り違える。after-bench.sh が検知する)
# usage:
#   bin/team.sh init                              ラベルを作る (Coordinator が開始時に1回。再実行してよい)
#   bin/team.sh claim <task_id> <title> [範囲]     オーケストレータの作業を Issue にする ($STATE/claims.tsv に task_id と Issue 番号)
#   bin/team.sh close <task_id> <結論>             その Issue に結論を書いて閉じる (Issue が無ければ何もしない)
#   bin/team.sh sync                              queue ラベルの PR を列に積み (task_id は pr-<番号>)、人が作業中の Issue を
#                                                 $STATE/human-claims.json に書き、両方を出す
#   bin/team.sh comment <pr-N|N> <本文>            PR にコメントする
set -uo pipefail
cd "$(dirname "$0")/.."
f=${ENV_FILE:-./env.sh}; [ -f "$f" ] && . "$f"
STATE=${STATE:-state}
: "${GH_REPO:?env.sh に GH_REPO=<owner/repo> (競技リポジトリ) を書く}"
gh_() { gh "$@" -R "$GH_REPO" </dev/null; }
# 本文の「範囲: ...」の行 (無ければ空)
AREA='(.body // "") | gsub("\r"; "") | split("\n") | map(select(test("^範囲[:：]"))) | (first // "") | sub("^範囲[:：]\\s*"; "")'

case ${1:-} in
  init)
    gh_ label create orchestrator --color 5319e7 --description "オーケストレータの作業 (結論が出たら閉じる)" --force
    gh_ label create queue --color 0e8a16 --description "main に入れたい PR。オーケストレータの列に積まれる" --force
    gh_ label create queued --color c5def5 --description "列に積んだ (ベンチ・採否の待ち)" --force
    gh_ label create restart --color d93f0b --description "OS の再起動でしか確かめられない変更 (再起動確認の対象)" --force ;;
  claim)
    tid=${2:?usage: team.sh claim <task_id> <title> [範囲]}; title=${3:?}
    url=$(gh_ issue create --title "$title" --label orchestrator \
      --body "$(printf '範囲: %s\norca task: %s\n\nオーケストレータが作業中。結論 (採用・revert・見送り) が出たら閉じます。' "${4:-}" "$tid")") || exit 1
    printf '%s\t%s\n' "$tid" "${url##*/}" >>"$STATE/claims.tsv"
    echo "#${url##*/}" ;;
  close)
    tid=${2:?usage: team.sh close <task_id> <結論>}
    n=$(awk -F'\t' -v t="$tid" '$1 == t { n = $2 } END { print n }' "$STATE/claims.tsv" 2>/dev/null)
    [ -n "$n" ] || { echo "team.sh: $tid の Issue は無い" >&2; exit 0; }
    gh_ issue close "$n" --comment "${3:-完了}" ;;
  comment)
    n=${2:?usage: team.sh comment <pr-N|N> <本文>}; n=${n#pr-}
    gh_ pr comment "$n" --body "${3:?}" >/dev/null ;;
  sync)
    q=$STATE/merge-queue.json; [ -f "$q" ] || echo '[]' >"$q"
    echo "## 列に積んだ PR (queue ラベル)"
    prs=$(gh_ pr list --state open --label queue --json number,title,headRefName,body,author,labels) || { echo "ERR gh pr list に失敗"; prs='[]'; }
    added=0
    for n in $(echo "$prs" | jq -r '.[].number' | sort -n); do
      e=$(echo "$prs" | jq -c --argjson n "$n" ".[] | select(.number == \$n) | {task_id: \"pr-\\(.number)\", pr: .number, branch: .headRefName,
        title: \"PR#\\(.number) \\(.title)\", author: .author.login, area: ($AREA), expected_gain: \"mid\",
        restart_risk: any(.labels[]; .name == \"restart\"), batchable: false, targets: []}")
      jq -e --arg t "pr-$n" 'any(.[]; .task_id == $t)' "$q" >/dev/null || bin/queue.sh add "$e" >/dev/null
      gh_ pr edit "$n" --remove-label queue --add-label queued >/dev/null || echo "ERR PR#$n のラベルを替えられない (次の sync でもう一度積もうとする)"
      gh_ pr comment "$n" --body "オーケストレータのマージ待ちの列に積みました。人の PR は列の先頭に並び、1件ずつベンチで測って採否を決めます。結果はここにコメントします。main と競合したらコメントするので、リベースして push してください (ラベルの付け直しは不要)。" >/dev/null
      echo "$e" | jq -r '"\(.task_id) \(.title) (@\(.author)) branch=\(.branch)\(if .area != "" then " 範囲: \(.area)" else "" end)"'
      added=$((added + 1))
    done
    [ "$added" = 0 ] && echo "なし"
    echo; echo "## 人が作業中 (orchestrator ラベルの無い open な Issue。範囲が重なる仮説は起動しない)"
    if iss=$(gh_ issue list --state open --limit 100 --json number,title,body,assignees,labels,author); then
      echo "$iss" | jq "[.[] | select(all(.labels[]; .name != \"orchestrator\")) | {number, title,
        who: ([.assignees[].login] | if length == 0 then null else join(\",\") end) // .author.login, area: ($AREA)}]" >"$STATE/human-claims.json"
      jq -r 'if length == 0 then "なし" else .[] | "#\(.number) @\(.who) \(.title)\(if .area != "" then " (範囲: \(.area))" else "" end)" end' "$STATE/human-claims.json"
    else echo "ERR gh issue list に失敗 ($STATE/human-claims.json は前回のまま)"; fi ;;
  *) sed -n '2,13p' "$0" >&2; exit 2 ;;
esac
