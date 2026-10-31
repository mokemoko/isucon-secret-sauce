#!/usr/bin/env bash
# usage: pgact-sampler.sh <pgact-sampler.raw> <元の出力の保存先>
# pgact-sampler.collect.sh の出力 (サンプリングと pre/post の統計。同じディレクトリの pgact-sampler.{pre,post}.tsv) → <host>/pgact.json (stdout)
#   ticks / sec            : サンプル回数とその期間 (秒)
#   active_avg             : 1回あたりの idle 以外のセッション数の平均 (DB に仕事が詰まっている度合い)
#   waits[]                : {state, wait (wait_event_type:wait_event。空は CPU で実行中), sessions (1回あたりの平均), share}
#                            Client:ClientRead かつ idle in transaction は「トランザクション中にアプリの次の文を待っている」(RTT 待ちでロックを持ち続ける)
#   lock_waits[]           : {waiting (待っている文), blocker (待たせている側の文。実行中か、idle in transaction なら最後の文), blocker_state, wait, samples, sessions}
#   top_queries[]          : {query, samples, sessions, waits:{...}} 実行中 (idle in transaction 以外) の文の上位 (サンプル数 = 時間に比例)
#   tables[]               : {table (パーティションの _YYYYMM 等の数字の接尾辞はまとめる), read_mb (heap+idx+toast+toast idx のディスク等からの読み), hit_mb, heap_read_mb, toast_read_mb, idx_read_mb}
#   io[]                   : pg_stat_io の差分 {backend_type, object, context, read_mb, read_ms, write_mb, hit_mb}
set -euo pipefail
in=$1 raw=$2
d=$(dirname "$in")
cp "$in" "$raw"
tsv() { [ -s "$1" ] && jq -Rn '[inputs | split("\t")]' "$1" || echo '[]'; }
jq -n --slurpfile pre <(tsv "$d/pgact-sampler.pre.tsv") --slurpfile post <(tsv "$d/pgact-sampler.post.tsv") --rawfile s "$in" '
  def r: . * 10 | round / 10;
  def mb($n; $b): ($n | tonumber? // 0) * $b / 1048576;
  ($s | split("\n") | map(select(length > 0) | split("\t"))) as $rows
  | ($rows | map(select(.[0] == "T") | .[1] | tonumber)) as $t
  | ($t | length) as $n
  | ($rows | map(select(.[0] == "S" and length >= 9)
      | {pid: .[1], state: .[2], wait: (if .[3] == "" then "" else .[3] + ":" + .[4] end), query: .[5], blockers: .[6], bq: .[7], bs: .[8]})) as $ss
  | def per: if $n > 0 then (. / $n * 100 | round / 100) else 0 end;
  # 統計の差分: key の列で突き合わせ、数値の列を post - pre にする
  def delta($k; $from): ($pre[0] | map(select(.[0] == $k)) | map({key: (.[1:$from] | join("|")), value: .}) | from_entries) as $p
    | $post[0] | map(select(.[0] == $k)) | map(. as $row | ($p[.[1:$from] | join("|")] // []) as $q
      | [range(0; length)] | map(if . < $from then $row[.] else (($row[.] | tonumber? // 0) - ($q[.] | tonumber? // 0)) end));
  {ticks: $n, sec: (if $n > 1 then ($t[-1] - $t[0]) | r else 0 end),
   active_avg: ($ss | length | per),
   waits: ($ss | group_by([.state, .wait]) | map({state: .[0].state, wait: .[0].wait, sessions: (length | per), share: (length / ([$ss | length, 1] | max) * 1000 | round / 10)}) | sort_by(-.sessions)),
   lock_waits: ($ss | map(select(.wait | startswith("Lock:"))) | group_by([.query, .bq, .bs, .wait])
     | map({waiting: .[0].query, blocker: .[0].bq, blocker_state: .[0].bs, wait: .[0].wait, samples: length, sessions: (length | per)}) | sort_by(-.samples) | .[0:20]),
   top_queries: ($ss | map(select(.state != "idle in transaction")) | group_by(.query)
     | map({query: .[0].query, samples: length, sessions: (length | per), waits: (group_by(.wait) | map({(.[0].wait): length}) | add)}) | sort_by(-.samples) | .[0:20]),
   tables: (delta("R"; 2) | map({table: (.[1] | sub("_[0-9]+$"; "")), heap: (.[2]), hh: .[3], idx: .[4], ih: .[5], toast: (.[6] + .[8]), th: (.[7] + .[9])})
     | group_by(.table) | map({table: .[0].table, read_mb: (map(.heap + .idx + .toast) | add | mb(.; 8192) | r), hit_mb: (map(.hh + .ih + .th) | add | mb(.; 8192) | r),
       heap_read_mb: (map(.heap) | add | mb(.; 8192) | r), toast_read_mb: (map(.toast) | add | mb(.; 8192) | r), idx_read_mb: (map(.idx) | add | mb(.; 8192) | r)})
     | map(select(.read_mb + .hit_mb > 0)) | sort_by(-.read_mb, -.hit_mb) | .[0:20]),
   io: (delta("I"; 4) | map(.[8] as $b | {backend_type: .[1], object: .[2], context: .[3], read_mb: (mb(.[4]; 8192) | r), read_ms: (.[5] | round), write_mb: (mb(.[6]; 8192) | r), hit_mb: (mb(.[7]; 8192) | r)})
     | map(select(.read_mb + .write_mb + .hit_mb > 0)) | sort_by(-.read_mb))}'
