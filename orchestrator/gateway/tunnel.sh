#!/usr/bin/env bash
# オーケストレータの PC のダッシュボード (127.0.0.1:$PORT) を、gateway の EC2 の 127.0.0.1:$PORT に転送し続ける。切れたら張り直す
# ダッシュボードと同じ PC で、ダッシュボードとは別のターミナルで動かす (Ctrl-C で止める)
set -uo pipefail
DIR=${DIR:-$HOME/isucon/gateway}
PORT=${PORT:-9180}
while :; do
  ssh -F "$DIR/ssh_config" -N -o ExitOnForwardFailure=yes -R "127.0.0.1:$PORT:127.0.0.1:$PORT" isucon-gateway
  echo "tunnel: 切れた ($(date +%T))。3秒後に張り直す" >&2
  sleep 3
done
