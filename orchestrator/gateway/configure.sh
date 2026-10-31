#!/usr/bin/env bash
# gateway の Caddy の設定を書き直す (DOMAIN)。up.sh が最後に呼ぶ。独自ドメインへの切り替えで再実行してよい
# usage: [DOMAIN=<名前>] gateway/configure.sh
# 証明書の取得 (Let's Encrypt の HTTP-01。検証元の IP は決まっていない) の間だけ 80 を全体に開け、取れたら閉じる。
# 一日の競技では更新 (60日後) が来ないので、閉じたままでよい
set -euo pipefail
DIR=${DIR:-$HOME/isucon/gateway}
PORT=${PORT:-9180}   # ダッシュボードの待ち受け (tunnel.sh が EC2 の 127.0.0.1:$PORT に転送する)
pub=$(cat "$DIR/ip")
DOMAIN=${DOMAIN:-${pub//./-}.sslip.io}
s() { ssh -F "$DIR/ssh_config" isucon-gateway "$@"; }
# アクセスログは出さない (URL に計測の id が入る)
s "sudo tee /etc/caddy/Caddyfile >/dev/null" <<C
$DOMAIN {
  reverse_proxy 127.0.0.1:$PORT
}
C
sg=$(cat "$DIR/sg")
http80() { aws ec2 "$1-security-group-ingress" --group-id "$sg" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null 2>&1; }
http80 authorize || true   # 既に開いていれば失敗するが構わない
trap 'http80 revoke || echo "80 を閉じられなかった。aws ec2 revoke-security-group-ingress --group-id $sg --protocol tcp --port 80 --cidr 0.0.0.0/0" >&2' EXIT
s 'sudo systemctl reload caddy || sudo systemctl restart caddy'
echo "$DOMAIN" >"$DIR/domain"
echo "証明書の取得待ち..." >&2
ok=
for _ in $(seq 60); do
  # 証明書が取れるまでは TLS の検証で失敗する (000)。取れたら 200 (トンネルが無ければ 502) が返る
  [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://$DOMAIN/")" != 000 ] && { ok=1; break; }
  sleep 3
done
[ -n "$ok" ] || { echo "証明書を取れなかった (3分)。ssh -F $DIR/ssh_config isucon-gateway journalctl -u caddy で理由を見る" >&2; exit 1; }
echo "URL: https://$DOMAIN/"
