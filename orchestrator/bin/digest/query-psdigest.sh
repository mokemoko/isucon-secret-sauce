#!/usr/bin/env bash
# usage: query-psdigest.sh <query-psdigest.raw> <元の出力の保存先>
# query-psdigest.collect.sh の TSV → queries スキーマ (stdout)。時間はピコ秒から秒に直す。
# slow log 版 (query-pt) に無い項目として no_index_used (インデックス未使用の回数)・tmp_disk_tables を足す
set -euo pipefail
raw=$1 out=$2
cp "$raw" "$out"
jq -Rn '
  def ps: tonumber? // 0 | . / 1e12;
  def num: tonumber? // 0;
  # mysql -B は改行・タブ・バックスラッシュを \n \t \\ にエスケープする
  def unesc: gsub("\\\\(?<c>.)"; if .c == "n" then "\n" elif .c == "t" then "\t" elif .c == "0" then "" else .c end);
  def clean: gsub("[\u0001-\u0008\u000b-\u001f\u007f]"; "");
  [inputs | split("\t") | select(length >= 13) | (.[1] | num) as $n | {
    fingerprint: (.[0] | unesc | clean | .[0:500]), count: $n,
    sum: (.[2] | ps), avg: (.[3] | ps), p95: (.[5] | ps), max: (.[4] | ps),
    rows_examined_avg: (if $n > 0 then (.[6] | num) / $n | . * 10 | round / 10 else 0 end),
    rows_sent_avg: (if $n > 0 then (.[7] | num) / $n | . * 10 | round / 10 else 0 end),
    no_index_used: ((.[8] | num) + (.[9] | num)), tmp_disk_tables: (.[10] | num),
    sample: (.[12] | if . == "NULL" then "" else unesc | clean | .[0:300] end)
  }] | sort_by(-.sum)' "$raw"
