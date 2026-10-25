#!/usr/bin/env bash
# usage: dns-pdns.sh <dns-pdns.post.json> <元の出力の保存先>
# 同じディレクトリの dns-pdns.pre.json との差分から、ベンチ中の PowerDNS の問い合わせ数・応答の内訳・backend の問い合わせ数を出す。
#   {sec, restarted, queries:{udp,tcp}, answers:{udp,tcp}, rcode:{noerror,nxdomain,servfail}, backend_queries,
#    drops:{overload,timedout,udp_recvbuf,udp_in,corrupt}, cpu_sec:{user,sys}, latency_us:{all,backend,receive,send,qsize}}
# 統計に無い項目は null。latency_us は pdns の移動平均 (直近の問い合わせの平均。ベンチ終わりの値) で、差分ではない。restarted=true ならベンチ中に再起動しており差分は post の累積
set -euo pipefail
post=$1 raw=$2
pre=${post%.post.json}.pre.json
kv() { jq 'map(select(.type == "StatisticItem") | {(.name): (.value | tonumber)}) | add' "$1"; }
kv "$post" >"$raw"
jq -n --argjson a "$( [ -s "$pre" ] && kv "$pre" || echo '{}')" --argjson b "$(cat "$raw")" '
  ($b.uptime < ($a.uptime // 0) or ($a | length) == 0) as $r
  | def d(k): if $b[k] == null then null else $b[k] - (if $r then 0 else ($a[k] // 0) end) end;
  {sec: (if $r then $b.uptime else $b.uptime - $a.uptime end), restarted: $r,
   queries: {udp: d("udp-queries"), tcp: d("tcp-queries")}, answers: {udp: d("udp-answers"), tcp: d("tcp-answers")},
   rcode: {noerror: d("noerror-packets"), nxdomain: d("nxdomain-packets"), servfail: d("servfail-packets")},
   backend_queries: d("backend-queries"),
   drops: {overload: d("overload-drops"), timedout: d("timedout-packets"), udp_recvbuf: d("udp-recvbuf-errors"), udp_in: d("udp-in-errors"), corrupt: d("corrupt-packets")},
   cpu_sec: {user: (d("user-msec") | if . then . / 1000 else null end), sys: (d("sys-msec") | if . then . / 1000 else null end)},
   latency_us: {all: $b.latency, backend: $b["backend-latency"], receive: $b["receive-latency"], send: $b["send-latency"], qsize: $b["qsize-q"]}}'
