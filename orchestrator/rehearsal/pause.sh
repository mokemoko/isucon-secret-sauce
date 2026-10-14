#!/usr/bin/env bash
# usage: rehearsal/pause.sh stop|start   リハーサルを中断・再開する (本番では使わない)
#   stop : タグ Project=isucon-rehearsal のインスタンスを止め、停止時刻を $STATE/paused_at に残す
#   start: 起動し、変わったパブリック IP を ~/isucon/ssh_config・$DIR/ssh_config・$DIR/hosts.tsv・$STATE/docs/hosts.txt に反映する。
#          マージ待ちの列の ready_at を停止していた分だけ進め、待ち時間に中断を数えない (リハ#2 で順位が待ち時間順に崩れた)
#          $STATE/end (競技終了時刻) も停止していた分だけ延ばす。Coordinator とダッシュボードはこれを読み直す (リハ#3 で延長幅を見込みで決めて Phase 3 を過ぎた)
# ホストの名前は tag Name (up.sh が isu1.. と bench を付ける)。プライベート IP は停止しても変わらない
set -euo pipefail
cd "$(dirname "$0")/.."
STATE=${STATE:-state}; DIR=${DIR:-$HOME/isucon/rehearsal}
f=Name=tag:Project,Values=isucon-rehearsal
ids=$(aws ec2 describe-instances --filters $f Name=instance-state-name,Values=running,stopped,stopping,pending \
  --query 'Reservations[].Instances[].InstanceId' --output text)
case ${1:-} in
  stop)
    aws ec2 stop-instances --instance-ids $ids >/dev/null && aws ec2 wait instance-stopped --instance-ids $ids
    date +%s >"$STATE/paused_at"; echo "stopped $ids" ;;
  start)
    aws ec2 start-instances --instance-ids $ids >/dev/null && aws ec2 wait instance-running --instance-ids $ids
    aws ec2 describe-instances --instance-ids $ids --output text \
      --query 'Reservations[].Instances[].[Tags[?Key==`Name`]|[0].Value,PublicIpAddress,PrivateIpAddress]' | sort >"$DIR/hosts.tsv"
    for c in "$HOME/isucon/ssh_config" "$DIR/ssh_config"; do
      [ -f "$c" ] || continue
      awk -v map="$DIR/hosts.tsv" 'BEGIN { while ((getline l < map) > 0) { split(l, a, "\t"); ip[a[1]] = a[2] } }
        $1 == "Host" { h = $2 } $1 == "HostName" && (h in ip) { sub(/HostName .*/, "HostName " ip[h]) } { print }' "$c" >"$c.tmp" && mv "$c.tmp" "$c"
    done
    grep -v '^bench' "$DIR/hosts.tsv" | cut -f1,2 | tr '\t' ' ' >"$STATE/docs/hosts.txt"
    if [ -f "$STATE/paused_at" ]; then
      d=$(( $(date +%s) - $(cat "$STATE/paused_at") ))
      [ -f "$STATE/merge-queue.json" ] && jq --argjson d "$d" 'map(.ready_at += $d)' "$STATE/merge-queue.json" >"$STATE/mq.tmp" && mv "$STATE/mq.tmp" "$STATE/merge-queue.json"
      if [ -f "$STATE/end" ]; then
        e=$(cat "$STATE/end"); ts=$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "${e%:*}${e##*:}" +%s)
        n=$(date -r $((ts + d)) +%Y-%m-%dT%H:%M:%S%z); echo "${n%??}:${n: -2}" >"$STATE/end"
        echo "end: $e -> $(cat "$STATE/end") (+$((d / 60))分)"
      fi
      rm "$STATE/paused_at"
    fi
    cat "$DIR/hosts.tsv"
    echo "started (known_hosts の古い鍵で ssh が拒否されたら ssh-keygen -R <ip>)" ;;
  *) sed -n 2,6p "$0" >&2; exit 2 ;;
esac
