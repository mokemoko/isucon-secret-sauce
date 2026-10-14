#!/usr/bin/env bash
# judge.sh: 直近3回の中央値を基準、同じ sha の組からノイズ幅、2回続けて割ったら revert
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export STATE=$t
row() { printf '{"id":"%s","sha":"%s","pass":%s,"score":%s}\n' "$@" >>"$t/bench.jsonl"; }
j() { "$root/bin/judge.sh" "$1" | sed 's/ .*//'; }
echo 0.26 >"$t/noise"
row b1 s1 true 1000; row b2 s1 true 900          # 同じ sha の組: 差 10%
row b3 s2 true 2000; row b4 s3 true 3000; row b5 s4 true 6000   # 6000 はたまたま高い1回
row b6 s5 true 2800                               # 基準 = 中央値(2000,3000,6000)=3000、ノイズ 0.1 → 2700 以上で採用
[ "$(j b6)" = verdict=adopt ] || { echo "FAIL adopt: $("$root/bin/judge.sh" b6)"; exit 1; }
row b7 s6 true 2500
[ "$(j b7)" = verdict=retry ] || { echo "FAIL retry"; exit 1; }
row b8 s6 true 2400                               # 同じ sha で2回目も割る
[ "$(j b8)" = verdict=revert ] || { echo "FAIL revert: $("$root/bin/judge.sh" b8)"; exit 1; }
row b9 s7 true 2900                               # revert した s6 は基準から除く: 中央値(3000,6000,2800)=3000
"$root/bin/judge.sh" b9 | grep -q 'ref=3000 ' || { echo "FAIL ref excludes revert: $("$root/bin/judge.sh" b9)"; exit 1; }
row b10 s8 false 0
[ "$(j b10)" = verdict=human ] || { echo "FAIL human"; exit 1; }
"$root/bin/judge.sh" b10 >/dev/null   # 判定し直しは置き換え
[ "$(wc -l <"$t/verdicts.jsonl" | tr -d ' ')" = 5 ] || { echo "FAIL ledger"; exit 1; }
echo ok
