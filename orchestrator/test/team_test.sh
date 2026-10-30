#!/usr/bin/env bash
# team.sh: 作業の宣言 (Issue) と人の PR の取り込み。偽の gh で呼び出しを記録する
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir "$t/bin" "$t/state"
cat >"$t/bin/gh" <<'S'
#!/usr/bin/env bash
echo "$*" >>"$T/gh.log"
case "$1 $2" in
  "issue create") echo "https://github.com/o/r/issues/12" ;;
  "pr list") cat <<'J'
[{"number":5,"title":"users に index","headRefName":"alice/idx","body":"説明\r\n範囲: users テーブル\r\n","author":{"login":"alice"},"labels":[{"name":"queue"}]},
 {"number":6,"title":"sysctl","headRefName":"bob/sysctl","body":"","author":{"login":"bob"},"labels":[{"name":"queue"},{"name":"restart"}]}]
J
  ;;
  "issue list") cat <<'J'
[{"number":12,"title":"オーケストレータの作業","body":"範囲: nginx","assignees":[],"labels":[{"name":"orchestrator"}],"author":{"login":"me"}},
 {"number":13,"title":"画像を nginx で返す","body":"範囲：GET /icon","assignees":[{"login":"carol"}],"labels":[],"author":{"login":"dave"}},
 {"number":14,"title":"調査","body":null,"assignees":[],"labels":[],"author":{"login":"erin"}}]
J
  ;;
esac
S
chmod +x "$t/bin/gh"
export T=$t PATH="$t/bin:$PATH" STATE=$t/state GH_REPO=o/r ENV_FILE=/nonexistent
s=$root/bin/team.sh

# GH_REPO が無ければ動かない (別のリポジトリに書かないため)
if GH_REPO= $s sync 2>/dev/null; then echo "FAIL no GH_REPO"; exit 1; fi
$s init; [ "$(grep -c '^label create .* -R o/r$' "$t/gh.log")" = 4 ] || { echo "FAIL init"; cat "$t/gh.log"; exit 1; }

[ "$($s claim task_1 'index を足す' 'users テーブル')" = "#12" ] || { echo "FAIL claim"; exit 1; }
grep -q '^issue create --title index を足す --label orchestrator --body 範囲: users テーブル' "$t/gh.log" && grep -qx "task_1	12" "$t/state/claims.tsv" || { echo "FAIL claim log"; cat "$t/gh.log"; exit 1; }
$s close task_1 "採用 (bench 1)"; grep -q '^issue close 12 --comment 採用 (bench 1) -R o/r$' "$t/gh.log" || { echo "FAIL close"; exit 1; }
: >"$t/gh.log"; $s close task_none x 2>/dev/null; [ ! -s "$t/gh.log" ] || { echo "FAIL close unknown"; exit 1; }

out=$($s sync)
q=$t/state/merge-queue.json
[ "$(jq -c '[.[] | [.task_id, .branch, .area, .restart_risk, .batchable, .author]]' "$q")" = '[["pr-5","alice/idx","users テーブル",false,false,"alice"],["pr-6","bob/sysctl","",true,false,"bob"]]' ] || { echo "FAIL queue: $(cat "$q")"; exit 1; }
grep -q '^pr edit 5 --remove-label queue --add-label queued' "$t/gh.log" && grep -q '^pr comment 6 --body ' "$t/gh.log" || { echo "FAIL labels"; cat "$t/gh.log"; exit 1; }
[ "$(jq -c 'map([.number, .who, .area])' "$t/state/human-claims.json")" = '[[13,"carol","GET /icon"],[14,"erin",""]]' ] || { echo "FAIL claims: $(cat "$t/state/human-claims.json")"; exit 1; }
echo "$out" | grep -q '^pr-5 PR#5 users に index (@alice) branch=alice/idx 範囲: users テーブル$' && echo "$out" | grep -q '^#13 @carol 画像を nginx で返す (範囲: GET /icon)$' || { echo "FAIL out: $out"; exit 1; }
# 2回目 (ラベルの付け替えに失敗して残っていた) でも、列の待ち時間を振り出しに戻さない
jq 'map(.ready_at = 1)' "$q" >"$q.tmp" && mv "$q.tmp" "$q"; $s sync >/dev/null
[ "$(jq -c 'map(.ready_at)' "$q")" = '[1,1]' ] || { echo "FAIL re-add"; exit 1; }
$s comment pr-5 hello; tail -1 "$t/gh.log" | grep -q '^pr comment 5 --body hello -R o/r$' || { echo "FAIL comment"; exit 1; }
echo ok
