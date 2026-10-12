#!/usr/bin/env bash
# usage: bin/digest.sh <analysis/<id> ディレクトリ> [ベンチ結果 JSON]
# 回収したログ・プロファイルを、ツールに依存しない共通スキーマの JSON に変換し、AI 向けの summary.md を作る。
#   <host>/endpoints.json : [{method, uri, count, status:{1xx..5xx}, sum, avg, max, p90, p95, p99, body_sum, body_avg}] 秒・sum 降順
#   <host>/queries.json   : [{fingerprint, count, sum, avg, p95, max, rows_examined_avg, rows_sent_avg, sample}] 秒・sum 降順
#   <host>/profile.json   : {duration, samples, flat:[{func, flat, flat_pct, cum, cum_pct}], cum:[...]} 秒
#   summary.md            : 上記の上位だけを詰めたテキスト (AI はまずこれを読む)
# 変換は bin/digest/<kind>-<tool>.sh (引数 <入力> <元の出力の保存先>、stdout にスキーマ JSON)。
# ツールは env.sh の ACCESS_DIGEST / QUERY_DIGEST / PROFILE_DIGEST で選ぶ。別のツール (pgBadger 等) が要るならアダプタを1本足す
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . "${ENV_FILE:-./env.sh}"; set +a
dir=$1 result=${2:-}
ACCESS_DIGEST=${ACCESS_DIGEST:-alp} QUERY_DIGEST=${QUERY_DIGEST:-pt} PROFILE_DIGEST=${PROFILE_DIGEST:-pprof}

# 失敗しても他の変換とベンチ台帳は止めない。理由は digest.err に残す
run() { # kind tool input json raw
  local a=bin/digest/$1-$2.sh
  [ -x "$a" ] || { echo "$1: adapter $a がありません" >>"$dir/digest.err"; return; }
  "$a" "$3" "$5" >"$4.tmp" 2>>"$dir/digest.err" && jq -e 'type' "$4.tmp" >/dev/null 2>&1 \
    && mv "$4.tmp" "$4" || { rm -f "$4.tmp"; echo "$1: $3 の変換に失敗" >>"$dir/digest.err"; }
}
for f in "$dir"/*/access.log; do [ -s "$f" ] && run access "$ACCESS_DIGEST" "$f" "${f%/*}/endpoints.json" "${f%.log}.alp.txt"; done
for f in "$dir"/*/*slow*.log; do [ -s "$f" ] && run query "$QUERY_DIGEST" "$f" "${f%/*}/queries.json" "${f%.log}.pt.txt"; done
for f in "$dir"/*/cpu.pprof; do [ -s "$f" ] && run profile "$PROFILE_DIGEST" "$f" "${f%/*}/profile.json" "${f%/*}/pprof.txt"; done

{
  echo "# bench $(basename "$dir")"
  [ -n "$result" ] && echo "$result" | jq -r '"pass=\(.pass) score=\(.score)" + (if .error then " error=\(.error)" else "" end)'
  ms() { echo 'def ms: . * 1000 | round | tostring + "ms"; def sh(t): if t > 0 then (. / t * 100 | round | tostring) + "%" else "-" end;'; }
  for f in "$dir"/*/endpoints.json; do
    [ -f "$f" ] || continue
    echo; jq -r "$(ms)"' (map(.sum) | add) as $t | (map(.count) | add) as $n |
      "## endpoints \(input_filename | split("/")[-2]) total=\($t * 10 | round / 10)s req=\($n)",
      "share sum avg p99 count 4xx 5xx method uri",
      (.[0:12][] | "\(.sum | sh($t)) \(.sum * 10 | round / 10)s \(.avg | ms) \(.p99 | ms) \(.count) \(.status["4xx"]) \(.status["5xx"]) \(.method) \(.uri)"),
      (if length > 12 then "(他 \(length - 12) 件 \((.[12:] | map(.sum) | add) * 10 | round / 10)s)" else empty end)' "$f"
  done
  for f in "$dir"/*/queries.json; do
    [ -f "$f" ] || continue
    echo; jq -r "$(ms)"' (map(.sum) | add) as $t |
      "## queries \(input_filename | split("/")[-2]) total=\($t * 10 | round / 10)s (上位 \(length) 種)",
      "share sum avg p95 count rows_examined/q fingerprint",
      (.[0:10][] | "\(.sum | sh($t)) \(.sum * 10 | round / 10)s \(.avg | ms) \(.p95 | ms) \(.count) \(.rows_examined_avg) \(.fingerprint | .[0:240])")' "$f"
  done
  for f in "$dir"/*/profile.json; do
    [ -f "$f" ] || continue
    echo; jq -r '"## cpu profile \(input_filename | split("/")[-2]) samples=\(.samples)s / \(.duration)s",
      "flat% cum% func (flat 上位)", (.flat[0:12][] | "\(.flat_pct)% \(.cum_pct)% \(.func)"),
      "flat% cum% func (cum 上位のうちアプリの main パッケージ)", (.cum | map(select(.func | startswith("main."))) | .[0:10][] | "\(.flat_pct)% \(.cum_pct)% \(.func)")' "$f"
  done
  if [ -s "$dir/digest.err" ]; then echo; echo "## digest errors"; cat "$dir/digest.err"; fi
} >"$dir/summary.md"
[ -s "$dir/digest.err" ] || rm -f "$dir/digest.err"
