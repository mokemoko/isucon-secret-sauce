#!/usr/bin/env bash
# usage: rehearsal/pause.sh stop|start   リハーサルを中断・再開する (本番では使わない)
#   stop : タグ Project=isucon-rehearsal のインスタンスを止め、停止時刻を $STATE/paused_at に残す
#   start: 起動し、変わったパブリック IP を ~/isucon/ssh_config・$DIR/ssh_config・$STATE/docs/hosts.txt に反映する。
#          マージ待ちの列の ready_at を停止していた分だけ進め、待ち時間に中断を数えない (リハ#2 で順位が待ち時間順に崩れた)
# 1台構成 (isu1) 前提
set -euo pipefail
cd "$(dirname "$0")/.."
STATE=${STATE:-state}; DIR=${DIR:-$HOME/isucon/rehearsal}
f=Name=tag:Project,Values=isucon-rehearsal
id=$(aws ec2 describe-instances --filters $f Name=instance-state-name,Values=running,stopped,stopping,pending \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)
case ${1:-} in
  stop)
    aws ec2 stop-instances --instance-ids "$id" >/dev/null && aws ec2 wait instance-stopped --instance-ids "$id"
    date +%s >"$STATE/paused_at"; echo "stopped $id" ;;
  start)
    aws ec2 start-instances --instance-ids "$id" >/dev/null && aws ec2 wait instance-running --instance-ids "$id"
    ip=$(aws ec2 describe-instances --instance-ids "$id" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    for c in "$HOME/isucon/ssh_config" "$DIR/ssh_config"; do
      [ -f "$c" ] && sed -i '' "s/^\( *HostName \).*/\1$ip/" "$c"
    done
    echo "isu1 $ip" >"$STATE/docs/hosts.txt"
    if [ -f "$STATE/paused_at" ]; then
      d=$(( $(date +%s) - $(cat "$STATE/paused_at") ))
      [ -f "$STATE/merge-queue.json" ] && jq --argjson d "$d" 'map(.ready_at += $d)' "$STATE/merge-queue.json" >"$STATE/mq.tmp" && mv "$STATE/mq.tmp" "$STATE/merge-queue.json"
      rm "$STATE/paused_at"
    fi
    echo "started $id $ip (known_hosts の古い鍵で ssh が拒否されたら ssh-keygen -R $ip)" ;;
  *) sed -n 2,6p "$0" >&2; exit 2 ;;
esac
