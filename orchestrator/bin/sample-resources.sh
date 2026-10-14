#!/usr/bin/env bash
# ベンチ中に競技サーバ上で動かすリソースサンプラー (Linux の /proc だけを読む。追加インストール不要)
# bench.sh が `ssh <host> "SAMPLER_ID=<bench id> timeout <秒> bash -s" < bin/sample-resources.sh > <host>/resources.raw` で起動する。
# 止め方: ベンチ後に bench.sh が /tmp/isu-sampler-<id>.pid の pid を ssh で kill する。
# 後備えとして、接続が切れれば次の echo が失敗して終わり、timeout でも必ず終わる。
# 出力 (1秒ごと、生のカウンタ。差分の計算は手元の bin/digest/resources-proc.sh で行う):
#   H ncpu=<n> clk=<CLK_TCK> page=<bytes>      (先頭1回)
#   T <epoch ms>
#   cpu <user> <nice> <system> <idle> <iowait> <irq> <softirq> <steal>
#   M <MemTotal kB> <MemAvailable kB>
#   N <rx bytes 合計> <tx bytes 合計>          (lo 以外)
#   D <read sectors 合計> <written sectors 合計> (パーティションでない物理ディスク)
#   P <pid> <comm> <utime+stime ticks> <rss pages>
set -u
pidf=/tmp/isu-sampler-${SAMPLER_ID:-x}.pid
echo $$ >"$pidf"; trap 'rm -f "$pidf"' EXIT; trap 'exit 0' TERM
echo "H ncpu=$(grep -c '^cpu[0-9]' /proc/stat) clk=$(getconf CLK_TCK) page=$(getconf PAGESIZE)"
while :; do
  {
    echo "T $(date +%s%3N)"
    head -n1 /proc/stat
    awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print "M", t, a}' /proc/meminfo
    awk -F'[: ]+' 'NR>2 && $2!="lo" {rx+=$3; tx+=$11} END{print "N", rx+0, tx+0}' /proc/net/dev
    awk '$3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]+|xvd[a-z]+|vd[a-z]+)$/ {r+=$6; w+=$10} END{print "D", r+0, w+0}' /proc/diskstats
    # comm は括弧内に空白を含みうるので ") " で分けてから読む。空白は _ にする
    # サンプラー自身 (この bash・その子の cat/awk/date/sleep・親の timeout) は除く
    cat /proc/[0-9]*/stat 2>/dev/null | awk -v self=$$ -v parent=$PPID '{
      i = index($0, ") "); c = substr($0, index($0, "(") + 1, i - index($0, "(") - 1); gsub(/ /, "_", c)
      split(substr($0, i + 2), a, " "); if ($1 == self || $1 == parent || a[2] == self) next
      print "P", $1, c, a[12] + a[13], a[22] }'
  } || exit 0
  sleep 1
done
