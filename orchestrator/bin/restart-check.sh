#!/usr/bin/env bash
# usage: bin/restart-check.sh [note]
# 全ホスト再起動 → PROBE_URLS の応答が再起動前と一致するまで待つ (データ永続化確認) → deploy 無しでベンチ
# 実行タイミング: restart_risk 付きタスクの採用後と最終チェックのみ
set -euo pipefail
cd "$(dirname "$0")/.."
. "${ENV_FILE:-./env.sh}"
TIMEOUT=${TIMEOUT:-300}

snapshot() { for u in $PROBE_URLS; do ssh -o ConnectTimeout=5 "$APP_HOST" "curl -fsS '$u'" || echo "ERR $u"; done | shasum; }

before=$(snapshot)
for h in $HOSTS; do ssh "$h" 'sudo systemctl reboot' || true; done
sleep 15

end=$(( $(date +%s) + TIMEOUT ))
until [ "$(snapshot 2>/dev/null)" = "$before" ]; do
  [ "$(date +%s)" -lt "$end" ] || { echo "restart-check FAILED: probe mismatch after ${TIMEOUT}s" >&2; exit 1; }
  sleep 5
done
echo "probe ok" >&2
SKIP_DEPLOY=1 exec bin/bench.sh HEAD "restart-check ${1:-}"
