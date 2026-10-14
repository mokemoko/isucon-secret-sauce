#!/usr/bin/env bash
# usage: profile-pprof.sh <cpu.pprof> <raw出力先>
# Go の CPU プロファイル → profile スキーマ (stdout)。flat/cum の上位 30 関数
set -euo pipefail
f=$1 raw=$2
# GOROOT が別の Go を指していると go tool pprof が見つからないため外す
pp() { env -u GOROOT go tool pprof "$@" "$f" 2>/dev/null; }
pp -top -cum -nodecount=30 >"$raw"
# 時間表記 (12ms / 1.5s / 2mins) を秒に
rows() { awk '$NF!="" && $2 ~ /%$/ && $5 ~ /%$/ {print $1"\t"$2"\t"$4"\t"$5"\t"substr($0, index($0,$6))}'; }
{
  pp -top -nodecount=30 | rows | sed 's/^/flat\t/'
  pp -top -cum -nodecount=30 | rows | sed 's/^/cum\t/'
  grep -m1 '^Duration:' "$raw" | sed 's/^/head\t/'
} | jq -Rn '
  def sec: if . == "0" then 0 else capture("(?<v>[0-9.]+)(?<u>[a-z]+)") | (.v|tonumber) * ({"ns":1e-9,"us":1e-6,"ms":1e-3,"s":1,"mins":60,"hrs":3600}[.u] // 1) end;
  def pct: rtrimstr("%") | tonumber;
  [inputs | split("\t")] as $r
  | ($r | map(select(.[0]=="head"))[0][1] // "") as $h
  | { duration: ($h | capture("Duration: (?<d>[^,]+)").d? | sec?),
      samples: ($h | capture("Total samples = (?<s>[^ ]+)").s? | sec?),
      flat: [$r[] | select(.[0]=="flat") | {func: .[5], flat: (.[1]|sec), flat_pct: (.[2]|pct), cum: (.[3]|sec), cum_pct: (.[4]|pct)}],
      cum:  [$r[] | select(.[0]=="cum")  | {func: .[5], flat: (.[1]|sec), flat_pct: (.[2]|pct), cum: (.[3]|sec), cum_pct: (.[4]|pct)}] }'
