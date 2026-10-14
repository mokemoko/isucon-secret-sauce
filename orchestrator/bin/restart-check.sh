#!/usr/bin/env bash
# usage: bin/restart-check.sh [note]
# 全ホスト再起動 → PROBE_URLS の応答が再起動前と一致するまで待つ (データ永続化確認) → deploy 無しでベンチ
# 実行タイミング: restart_risk 付きの採用がたまったとき (coordinator.md の「再起動確認」) と最終チェック
set -euo pipefail
cd "$(dirname "$0")/.."
. "${ENV_FILE:-./env.sh}"
TIMEOUT=${TIMEOUT:-300}

# PROBE_URLS が空だと前後の比較が常に一致し、再起動の完了を待たずにベンチが走る (リハ#2)
[ -n "${PROBE_URLS// /}" ] || { echo "restart-check: env.sh の PROBE_URLS が空。再起動前後で比べる GET URL を書くこと" >&2; exit 2; }

snapshot() { for u in $PROBE_URLS; do ssh -o ConnectTimeout=5 "$APP_HOST" "curl -fsS '$u'" || echo "ERR $u"; done | shasum; }

before=$(snapshot)
case $(for u in $PROBE_URLS; do ssh -o ConnectTimeout=5 "$APP_HOST" "curl -fsS -o /dev/null '$u'" || echo ERR; done) in
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
SKIP_DEPLOY=1 exec "${BENCH_SH:-bin/bench.sh}" HEAD "restart-check ${1:-}"
