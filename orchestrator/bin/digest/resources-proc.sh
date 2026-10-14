#!/usr/bin/env bash
# usage: resources-proc.sh <resources.raw> <元の出力の保存先>
# bin/sample-resources.sh の生カウンタ → resources スキーマ (stdout):
#   {ncpu, t:[経過秒], host:{user,sys,iowait,steal,mem (% / 全コア・全メモリ比), rx,tx,rd,wr (bytes/s)},
#    procs:[{comm, cpu:[% / 1コア=100], rss:[MB], cpu_avg, cpu_max, rss_max}] (cpu_avg 降順、上位 10。同名プロセスは合算)}
set -euo pipefail
raw=$1 out=$2
awk '
  function fin(   i, dtot, dt, p, c) {
    if (!have) { have = 1; t0 = t } else {
      dt = (t - pt) / 1000; if (dt <= 0) dt = 1
      dtot = 0; for (i = 2; i <= 9; i++) dtot += cpu[i] - pcpu[i]; if (dtot <= 0) dtot = 1
      printf "S %.1f %.1f %.1f %.1f %.1f %.1f %.0f %.0f %.0f %.0f\n", (t - t0) / 1000,
        (cpu[2] + cpu[3] - pcpu[2] - pcpu[3]) / dtot * 100, (cpu[4] + cpu[7] + cpu[8] - pcpu[4] - pcpu[7] - pcpu[8]) / dtot * 100,
        (cpu[6] - pcpu[6]) / dtot * 100, (cpu[9] - pcpu[9]) / dtot * 100,
        mt ? (mt - ma) / mt * 100 : 0, (rx - prx) / dt, (tx - ptx) / dt, (rd - prd) * 512 / dt, (wr - pwr) * 512 / dt
      delete cc; delete cr
      for (p in ticks) { c = comm[p]; cr[c] += rss[p] * page / 1048576
        if ((p in pticks) && pcomm[p] == c && ticks[p] >= pticks[p]) cc[c] += (ticks[p] - pticks[p]) / clk / dt * 100 }
      for (c in cr) printf "C %.1f %s %.1f %.1f\n", (t - t0) / 1000, c, cc[c] + 0, cr[c]
    }
    pt = t; for (i = 2; i <= 9; i++) pcpu[i] = cpu[i]; prx = rx; ptx = tx; prd = rd; pwr = wr
    delete pticks; delete pcomm; for (p in ticks) { pticks[p] = ticks[p]; pcomm[p] = comm[p] }
    delete ticks; delete comm; delete rss
  }
  $1 == "H" { for (i = 2; i <= NF; i++) { split($i, kv, "="); h[kv[1]] = kv[2] } clk = h["clk"] + 0 ? h["clk"] : 100; page = h["page"] + 0 ? h["page"] : 4096; print "H", h["ncpu"] + 0 }
  $1 == "T" { if (t != "") fin(); t = $2 }
  $1 == "cpu" { for (i = 2; i <= 9; i++) cpu[i] = $i + 0 }
  $1 == "M" { mt = $2; ma = $3 }
  $1 == "N" { rx = $2; tx = $3 }
  $1 == "D" { rd = $2; wr = $3 }
  $1 == "P" { ticks[$2] = $4; comm[$2] = $3; rss[$2] = $5 }
  END { if (t != "") fin() }
' "$raw" | tee "$out" | jq -Rn '
  [inputs | split(" ")] as $l
  | ($l | map(select(.[0] == "S") | map(tonumber? // 0))) as $s
  | ($s | map(.[1])) as $t
  | ($l | map(select(.[0] == "C"))) as $c
  | def avg: if length > 0 then add / length else 0 end;
  {
    ncpu: ($l | map(select(.[0] == "H"))[0][1] // "0" | tonumber),
    t: $t,
    host: ([["user", 2], ["sys", 3], ["iowait", 4], ["steal", 5], ["mem", 6], ["rx", 7], ["tx", 8], ["rd", 9], ["wr", 10]]
      | map({(.[0]): (.[1] as $i | $s | map(.[$i]))}) | add),
    procs: ($c | group_by(.[2]) | map(
        (map({key: (.[1] | tonumber | tostring), value: [(.[3] | tonumber), (.[4] | tonumber)]}) | from_entries) as $m
        | {comm: .[0][2], cpu: [$t[] | tostring | $m[.][0] // 0], rss: [$t[] | tostring | $m[.][1] // 0]}
        | . + {cpu_avg: (.cpu | avg * 10 | round / 10), cpu_max: (.cpu | max), rss_max: (.rss | max)})
      | sort_by(-.cpu_avg) | .[0:10])
  }'
