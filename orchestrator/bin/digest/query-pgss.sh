#!/usr/bin/env bash
# usage: query-pgss.sh <query-pgss.raw> <元の出力の保存先>
# query-pgss.collect.sh の TSV → queries スキーマ (stdout)。時間はミリ秒から秒に直す。
# pg_stat_statements に p95 は無いので mean + 2*stddev を入れる (summary では p95 を目安として読む)。rows_examined_avg は無いので null。
# 足す項目: blks_read (共有バッファに無くディスク等から読んだブロック数)・hit_ratio
set -euo pipefail
raw=$1 out=$2
cp "$raw" "$out"
jq -Rn '
  def num: tonumber? // 0;
  def ms: num / 1000;
  [inputs | split("\t") | select(length >= 9) | (.[1] | num) as $n | (.[7] | num) as $hit | (.[8] | num) as $read | {
    fingerprint: (.[0] | .[0:500]), count: $n,
    sum: (.[2] | ms), avg: (.[3] | ms), p95: ((.[3] | ms) + 2 * (.[5] | ms)), max: (.[4] | ms),
    rows_examined_avg: null,
    rows_sent_avg: (if $n > 0 then (.[6] | num) / $n | . * 10 | round / 10 else 0 end),
    blks_read: $read, hit_ratio: (if $hit + $read > 0 then $hit / ($hit + $read) | . * 1000 | round / 1000 else null end),
    sample: (.[0] | .[0:300])
  }] | sort_by(-.sum)' "$raw"
