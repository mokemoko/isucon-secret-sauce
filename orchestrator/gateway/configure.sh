#!/usr/bin/env bash
# gateway の Caddy の設定を書き直す ($DIR/users.txt の利用者と DOMAIN)。up.sh が最後に呼ぶ。利用者の追加・独自ドメインへの切り替えで再実行してよい
# usage: [DOMAIN=<名前>] gateway/configure.sh
set -euo pipefail
DIR=${DIR:-$HOME/isucon/gateway}
PORT=${PORT:-9180}   # ダッシュボードの待ち受け (tunnel.sh が EC2 の 127.0.0.1:$PORT に転送する)
pub=$(cat "$DIR/ip")
DOMAIN=${DOMAIN:-${pub//./-}.sslip.io}
s() { ssh -F "$DIR/ssh_config" isucon-gateway "$@"; }
auth=""
while read -r u p; do
  [ -n "$u" ] || continue
  auth="$auth    $u $(s "caddy hash-password --plaintext '$p'")"$'\n'
done <"$DIR/users.txt"
[ -n "$auth" ] || { echo "$DIR/users.txt に利用者が無い" >&2; exit 1; }
# アクセスログは出さない (URL に計測の id が入る)。X-Remote-User は Caddy が認証した名前で上書きする (利用者が偽れない)
s "sudo tee /etc/caddy/Caddyfile >/dev/null" <<C
$DOMAIN {
  basicauth {
$auth  }
  reverse_proxy 127.0.0.1:$PORT {
    header_up X-Remote-User {http.auth.user.id}
  }
}
C
s 'sudo systemctl reload caddy || sudo systemctl restart caddy'
echo "$DOMAIN" >"$DIR/domain"
echo "URL: https://$DOMAIN/  (利用者とパスワードは $DIR/users.txt。証明書の取得に数十秒かかる)"
