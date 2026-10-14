#!/usr/bin/env bash
# usage: bin/digest.sh <analysis/<id> ディレクトリ> [ベンチ結果 JSON]
# 回収したログ・プロファイルを、ツールに依存しない共通スキーマの JSON に変換し、AI 向けの summary.md を作る。
#   <host>/endpoints.json : [{method, uri, count, status:{1xx..5xx}, sum, avg, max, p90, p95, p99, body_sum, body_avg, weight}] 秒・sum 降順
#                           weight は $STATE/docs/scoring.json の成功1件あたりの重み (載っていなければ null)
#   <host>/queries.json   : [{fingerprint, count, sum, avg, p95, max, rows_examined_avg, rows_sent_avg, sample, (no_index_used, tmp_disk_tables)}] 秒・sum 降順
#   <host>/profile.json   : {duration, samples, flat:[{func, flat, flat_pct, cum, cum_pct}], cum:[...]} 秒
#   <host>/resources.json : {ncpu, t:[秒], host:{user,sys,iowait,steal,mem (%), rx,tx,rd,wr (B/s)}, procs:[{comm, cpu:[%/1コア], rss:[MB], cpu_avg, cpu_max, rss_max}]}
#   warnings.txt          : bench.txt のうち BENCH_WARN_RE (既定 'WARN|ERROR') に当たる行。整合性の警告・エラーの増減を見る (pass でも減点になりうる)
#   summary.md            : 上記の上位だけを詰めたテキスト (AI はまずこれを読む)
# 変換は bin/digest/<kind>-<tool>.sh (引数 <入力> <元の出力の保存先>、stdout にスキーマ JSON)。
# ツールは env.sh の ACCESS_DIGEST / QUERY_DIGEST / PROFILE_DIGEST で選ぶ。別のツール (pgBadger 等) が要るならアダプタを1本足す
set -uo pipefail
cd "$(dirname "$0")/.."
set -a; . "${ENV_FILE:-./env.sh}"; set +a
dir=$1 result=${2:-}
ACCESS_DIGEST=${ACCESS_DIGEST:-alp} QUERY_DIGEST=${QUERY_DIGEST:-psdigest} PROFILE_DIGEST=${PROFILE_DIGEST:-pprof} RESOURCES_DIGEST=${RESOURCES_DIGEST:-proc}

# 失敗しても他の変換とベンチ台帳は止めない。理由は digest.err に残す
run() { # kind tool input json raw
  local a=bin/digest/$1-$2.sh
  [ -x "$a" ] || { echo "$1: adapter $a がありません" >>"$dir/digest.err"; return; }
  "$a" "$3" "$5" >"$4.tmp" 2>>"$dir/digest.err" && jq -e 'type' "$4.tmp" >/dev/null 2>&1 \
    && mv "$4.tmp" "$4" || { rm -f "$4.tmp"; echo "$1: $3 の変換に失敗" >>"$dir/digest.err"; }
}
for f in "$dir"/*/access.log; do [ -s "$f" ] && run access "$ACCESS_DIGEST" "$f" "${f%/*}/endpoints.json" "${f%.log}.alp.txt"; done
# クエリ: pt は回収した slow log、それ以外は collect が置いた <host>/query-<tool>.raw を入力にする
if [ "$QUERY_DIGEST" = pt ]; then
  for f in "$dir"/*/*slow*.log; do [ -s "$f" ] && run query pt "$f" "${f%/*}/queries.json" "${f%.log}.pt.txt"; done
else
  for f in "$dir"/*/query-"$QUERY_DIGEST".raw; do [ -s "$f" ] && run query "$QUERY_DIGEST" "$f" "${f%/*}/queries.json" "${f%.raw}.txt"; done
fi
[ -s "$dir/collect.err" ] && cat "$dir/collect.err" >>"$dir/digest.err"

# 採点の重み: scoring.json の endpoints[] を method ("*" は任意) と uri で突き合わせる。
# uri は alp の matching_groups と同じく ^ で始まれば正規表現、それ以外は完全一致。最初に一致したものを使う。
# alp がまとめた uri は正規表現の文字列そのもの (^/posts/\d+$) なので、matching_groups と同じ文字列を書けば完全一致する
scoring=${SCORING:-$dir/../../docs/scoring.json}
if [ -f "$scoring" ]; then
  for f in "$dir"/*/endpoints.json; do
    [ -f "$f" ] || continue
    jq --slurpfile s "$scoring" 'map(. as $e | ([$s[0].endpoints[]? | select((.method == "*" or .method == $e.method)
        and (.uri as $p | $e.uri == $p or ($p | startswith("^")) and (try ($e.uri | ltrimstr("^") | test($p)) catch false)))][0]) as $m
      | . + {weight: ($m.weight // null)})' "$f" >"$f.tmp" 2>>"$dir/digest.err" && mv "$f.tmp" "$f" || rm -f "$f.tmp"
  done
fi
for f in "$dir"/*/resources.raw; do [ -s "$f" ] && run resources "$RESOURCES_DIGEST" "$f" "${f%/*}/resources.json" "${f%/*}/resources.txt"; done
[ -f "$dir/bench.txt" ] && { grep -E "${BENCH_WARN_RE:-WARN|ERROR}" "$dir/bench.txt" || true; } >"$dir/warnings.txt"
for f in "$dir"/*/cpu.pprof; do [ -s "$f" ] && run profile "$PROFILE_DIGEST" "$f" "${f%/*}/profile.json" "${f%/*}/pprof.txt"; done

{
  echo "# bench $(basename "$dir")"
  [ -n "$result" ] && echo "$result" | jq -r '"pass=\(.pass) score=\(.score)" + (if .error then " error=\(.error)" else "" end)'
  if [ -f "$dir/warnings.txt" ]; then
    echo "warnings=$(wc -l <"$dir/warnings.txt" | tr -d ' ') (bench.txt のうち BENCH_WARN_RE='${BENCH_WARN_RE:-WARN|ERROR}' の行。例は先頭3件)"
    head -n3 "$dir/warnings.txt" | cut -c1-200
  fi
  ms() { echo 'def ms: . * 1000 | round | tostring + "ms"; def sh(t): if t > 0 then (. / t * 100 | round | tostring) + "%" else "-" end;'; }
  for f in "$dir"/*/endpoints.json; do
    [ -f "$f" ] || continue
    echo; jq -r "$(ms)"' (map(.sum) | add) as $t | (map(.count) | add) as $n |
      "## endpoints \(input_filename | split("/")[-2]) total=\($t * 10 | round / 10)s req=\($n)",
      (if any(.[]; .weight != null) then "加点あり (weight>0) の時間比率 \(map(select((.weight // 0) > 0) | .sum) | add // 0 | sh($t))。weight は scoring.json の成功1件あたりの重み (- は未記載)" else empty end),
      "share sum avg p99 count 4xx 5xx weight method uri",
      (.[0:12][] | "\(.sum | sh($t)) \(.sum * 10 | round / 10)s \(.avg | ms) \(.p99 | ms) \(.count) \(.status["4xx"]) \(.status["5xx"]) \(.weight // "-") \(.method) \(.uri)"),
      (if length > 12 then "(他 \(length - 12) 件 \((.[12:] | map(.sum) | add) * 10 | round / 10)s)" else empty end)' "$f"
  done
  for f in "$dir"/*/queries.json; do
    [ -f "$f" ] || continue
    echo; jq -r "$(ms)"' (map(.sum) | add) as $t |
      "## queries \(input_filename | split("/")[-2]) total=\($t * 10 | round / 10)s (上位 \(length) 種)",
      "share sum avg p95 count rows_examined/q noindex fingerprint",
      (.[0:10][] | "\(.sum | sh($t)) \(.sum * 10 | round / 10)s \(.avg | ms) \(.p95 | ms) \(.count) \(.rows_examined_avg) \(.no_index_used // "-") \(.fingerprint | .[0:240])")' "$f"
  done
  for f in "$dir"/*/profile.json; do
    [ -f "$f" ] || continue
    echo; jq -r '"## cpu profile \(input_filename | split("/")[-2]) samples=\(.samples)s / \(.duration)s",
      "flat% cum% func (flat 上位)", (.flat[0:12][] | "\(.flat_pct)% \(.cum_pct)% \(.func)"),
      "flat% cum% func (cum 上位のうちアプリの main パッケージ)", (.cum | map(select(.func | startswith("main."))) | .[0:10][] | "\(.flat_pct)% \(.cum_pct)% \(.func)")' "$f"
  done
  for f in "$dir"/*/resources.json; do
    [ -f "$f" ] || continue
    echo; jq -r 'def avg: if length > 0 then add / length else 0 end; def r: . * 10 | round / 10;
      ([.host.user, .host.sys] | transpose | map(add)) as $busy |
      "## resources \(input_filename | split("/")[-2]) ncpu=\(.ncpu) \(.t | length)s",
      "host cpu(user+sys) avg=\($busy | avg | r)% max=\($busy | max // 0 | r)% iowait avg=\(.host.iowait | avg | r)% steal avg=\(.host.steal | avg | r)% mem max=\(.host.mem | max // 0 | r)%",
      "net rx/tx avg=\(.host.rx | avg / 1048576 | r)/\(.host.tx | avg / 1048576 | r)MB/s disk rd/wr avg=\(.host.rd | avg / 1048576 | r)/\(.host.wr | avg / 1048576 | r)MB/s",
      "cpu_avg% cpu_max% rss_max_MB comm (1コア=100%)", (.procs[0:8][] | "\(.cpu_avg) \(.cpu_max) \(.rss_max | round) \(.comm)")' "$f"
  done
  if [ -s "$dir/digest.err" ]; then echo; echo "## digest errors"; cat "$dir/digest.err"; fi
} >"$dir/summary.md"
[ -s "$dir/digest.err" ] || rm -f "$dir/digest.err"
