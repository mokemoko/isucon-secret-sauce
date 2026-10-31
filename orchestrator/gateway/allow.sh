#!/usr/bin/env bash
# gateway の入口 (443) と ssh (22) に入れる接続元を足す。出口の IP が変わって入れなくなったときに使う
# usage: [ALLOW_CIDRS="<CIDR> ..."] gateway/allow.sh     (省略時はこの PC の今の IP/32)
set -euo pipefail
DIR=${DIR:-$HOME/isucon/gateway}
sg=$(cat "$DIR/sg")
ALLOW_CIDRS=${ALLOW_CIDRS:-$(curl -fsS https://checkip.amazonaws.com)/32}
for c in $ALLOW_CIDRS; do
  case $c in 0.0.0.0/0|::/0) echo "全体 ($c) は渡せない" >&2; exit 1 ;; esac
  for p in 22 443; do
    aws ec2 authorize-security-group-ingress --group-id "$sg" --protocol tcp --port $p --cidr "$c" >/dev/null 2>&1 || echo "$c:$p は登録済みか失敗" >&2
  done
  echo "許可: $c (22, 443)"
done
