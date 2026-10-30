#!/usr/bin/env bash
# usage: bin/restart-check.sh [note]
# 本番サーバのロックを取る → 全ホスト再起動 → PROBE_URLS の応答が再起動前と一致するまで待つ (データ永続化確認) → deploy 無しでベンチ
# 実行タイミング: restart_risk 付きの採用がたまったとき (coordinator.md の「再起動確認」) と最終チェック
set -euo pipefail
cd "$(dirname "$0")/.."
. "${ENV_FILE:-./env.sh}"
TIMEOUT=${TIMEOUT:-300}

# PROBE_CURL_ARGS (任意) は両方の curl に足す引数。APP_HOST のシェルで展開されるので、cookie はサーバ側のコマンド置換で取る
# PROBE_URLS が空だと前後の比較が常に一致し、再起動の完了を待たずにベンチが走る (リハ#2)
[ -n "${PROBE_URLS// /}" ] || { echo "restart-check: env.sh の PROBE_URLS が空。再起動前後で比べる GET URL を書くこと" >&2; exit 2; }

snapshot() { for u in $PROBE_URLS; do ssh -o ConnectTimeout=5 "$APP_HOST" "curl -fsS ${PROBE_CURL_ARGS:-} '$u'" || echo "ERR $u"; done | shasum; }

# 再起動からベンチまで本番サーバのロックを持つ (再起動の途中に他の人の deploy・手作業が入らないように)。bench.sh には BENCH_LOCK_TOKEN で渡す
if [ -z "${BENCH_LOCK_TOKEN:-}" ]; then
  BENCH_LOCK_TOKEN=$(bin/lock.sh acquire "restart-check ${1:-}")
  trap 'bin/lock.sh release "$BENCH_LOCK_TOKEN"' EXIT
  trap 'exit 130' INT TERM
fi
export BENCH_LOCK_TOKEN

before=$(snapshot)
case $(for u in $PROBE_URLS; do ssh -o ConnectTimeout=5 "$APP_HOST" "curl -fsS ${PROBE_CURL_ARGS:-} -o /dev/null '$u'" || echo ERR; done) in
  *ERR*) echo "restart-check: 再起動前の時点で PROBE_URLS に失敗する URL がある" >&2; exit 2 ;;
esac
for h in $HOSTS; do ssh "$h" 'sudo systemctl reboot' || true; done
sleep "${REBOOT_GRACE:-15}"

end=$(( $(date +%s) + TIMEOUT ))
# 各ホストに ssh でき、systemd の起動が終わる (running か degraded) まで待つ
for h in $HOSTS; do
  until ssh -o ConnectTimeout=5 "$h" 'systemctl is-system-running --wait' 2>/dev/null | grep -qE '^(running|degraded)$'; do
    [ "$(date +%s)" -lt "$end" ] || { echo "restart-check FAILED: $h が ${TIMEOUT}s 以内に起動しない" >&2; exit 1; }
    sleep 5
  done
done
until [ "$(snapshot 2>/dev/null)" = "$before" ]; do
  [ "$(date +%s)" -lt "$end" ] || { echo "restart-check FAILED: probe mismatch after ${TIMEOUT}s" >&2; exit 1; }
  sleep 5
done
echo "probe ok" >&2
SKIP_DEPLOY=1 "${BENCH_SH:-bin/bench.sh}" HEAD "restart-check ${1:-}"
