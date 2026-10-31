#!/usr/bin/env bash
# usage: guard-journal.sh <guard-journal.raw> <元の出力の保存先>
# isureal-guard のベンチ中のログ → <host>/guard.json (stdout)
#   {bans, ban_failed, ips, by_reason:{<reason>: 件数}, stats:{lines, action_logs, failures, bans}}
#   bans は "banned:" の行数 (同じ IP の再 BAN も数える)、ips はその異なり数。
#   stats は guard の 30 秒ごとの累積カウンタ (起動から) の、ベンチ中の最初と最後の行の差 (2行未満なら null)
set -euo pipefail
in=$1 raw=$2
cp "$in" "$raw"
jq -Rn '
  [inputs] as $l
  | ($l | map(select(startswith("banned:")) | capture("ip=(?<ip>[^ ]+) reason=(?<reason>[^ ]+)"))) as $b
  | ($l | map(select(startswith("stats:")) | [scan("[a-z_]+=([0-9]+)") | .[0] | tonumber])) as $s
  | {bans: ($b | length), ban_failed: ($l | map(select(startswith("ban failed:"))) | length), ips: ($b | map(.ip) | unique | length),
     by_reason: ($b | group_by(.reason) | map({(.[0].reason): length}) | add // {}),
     stats: (if ($s | length) >= 2 then [$s[-1], $s[0]] | transpose | map(.[0] - .[1]) | {lines: .[0], action_logs: .[1], failures: .[2], bans: .[3]} else null end)}' "$in"
