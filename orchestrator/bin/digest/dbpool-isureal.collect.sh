#!/usr/bin/env bash
# usage: dbpool-isureal.collect.sh <pre|post> <host> <出力ディレクトリ>
# アプリ (Go、go/db_stats.go) が localhost:6060/debug/dbpool (と /debug/vars の db_pool) に出す database/sql の接続プールの統計を、
# ベンチ前後と実行中 (DBPOOL_INTERVAL 秒ごと、既定 1) に取り、差分を <出力>/dbpool.json に置く (digest.sh を通さずにここで作る)。
#   <出力>/dbpool-isureal.{pre,post}.json : 前後の値 (累積)
#   <出力>/dbpool-isureal.samples.jsonl   : 実行中の値 (1行1回)
#   <出力>/dbpool.json : {sec, max_open, wait_count, wait_sec, wait_avg_ms, in_use_avg, in_use_max, saturated_ratio, open_max, idle_min,
#                         max_idle_closed, max_lifetime_closed, timeline:[{t, in_use, idle, wait_count}]}
#     wait_* は接続の空き待ち (MaxOpenConns に達して待った回数と合計秒) の増分。in_use_avg・saturated_ratio はアプリ内の 100ms ごとの標本の増分から
#     (saturated_ratio = InUse が上限に張り付いていた割合)。in_use_max はベンチ前に 0 に戻した後の 100ms 標本の最大。timeline の wait_count はベンチ前からの増分
# PPROF_HOSTS (アプリが動く台) 以外のホストでは何もしない。アプリ側に無い (404) なら何も置かない
set -euo pipefail
phase=$1 host=$2 out=$3
case " ${PPROF_HOSTS:-${APP_HOST:-}} " in *" $host "*) ;; *) exit 0 ;; esac
url=${DBPOOL_URL:-http://localhost:6060/debug/dbpool}
iv=${DBPOOL_INTERVAL:-1}
stop='f=/tmp/isu-dbpool.pid; [ -f $f ] && kill -TERM -- -$(cat $f) 2>/dev/null; rm -f $f; true'
mkdir -p "$out"
case $phase in
  pre)
    ssh "$host" "curl -fsS '$url?reset_max=1'" >"$out/dbpool-isureal.pre.json" 2>/dev/null || { rm -f "$out/dbpool-isureal.pre.json"; exit 0; }
    ssh "$host" "$stop; setsid nohup timeout 1800 bash -c 'while :; do curl -fsS -m 1 \"$url\"; sleep $iv; done' </dev/null >/tmp/isu-dbpool.out 2>/dev/null & echo \$! >/tmp/isu-dbpool.pid"
    ;;
  post)
    ssh "$host" "$stop; cat /tmp/isu-dbpool.out 2>/dev/null" >"$out/dbpool-isureal.samples.jsonl" || true
    ssh "$host" "curl -fsS '$url'" >"$out/dbpool-isureal.post.json" 2>/dev/null || { rm -f "$out/dbpool-isureal.post.json"; exit 0; }
    [ -s "$out/dbpool-isureal.pre.json" ] || exit 0
    jq -n --slurpfile a "$out/dbpool-isureal.pre.json" --slurpfile b "$out/dbpool-isureal.post.json" \
      --slurpfile s <(jq -c 'select(type == "object")' "$out/dbpool-isureal.samples.jsonl" 2>/dev/null || true) '
      def r2: . * 100 | round / 100;
      $a[0] as $a | $b[0] as $b | ($b.samples - $a.samples) as $n | ($b.wait_count - $a.wait_count) as $wc
      | ($s | map(select(.unix_sec >= $a.unix_sec and .unix_sec <= $b.unix_sec))) as $s
      | {sec: ($b.unix_sec - $a.unix_sec | r2), max_open: $b.max_open,
         wait_count: $wc, wait_sec: ($b.wait_sec - $a.wait_sec | r2),
         wait_avg_ms: (if $wc > 0 then ($b.wait_sec - $a.wait_sec) * 1000 / $wc | r2 else 0 end),
         in_use_avg: (if $n > 0 then ($b.in_use_sum - $a.in_use_sum) / $n | r2 else null end),
         in_use_max: $b.in_use_max,
         saturated_ratio: (if $n > 0 then ($b.saturated_samples - $a.saturated_samples) / $n | r2 else null end),
         open_max: ([$s[].open] | max), idle_min: ([$s[].idle] | min),
         max_idle_closed: ($b.max_idle_closed - $a.max_idle_closed), max_lifetime_closed: ($b.max_lifetime_closed - $a.max_lifetime_closed),
         timeline: [$s[] | {t: (.unix_sec - $a.unix_sec | round), in_use, idle, wait_count: (.wait_count - $a.wait_count)}]}
    ' >"$out/dbpool.json" || rm -f "$out/dbpool.json"
    ;;
  *) echo "usage: $0 <pre|post> <host> <dir>" >&2; exit 2 ;;
esac
