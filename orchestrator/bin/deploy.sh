#!/usr/bin/env bash
# usage: bin/deploy.sh <ref>
# 全ホストで並列に fetch → checkout → make deploy。APP_HOST にデプロイした sha を出力する
set -euo pipefail
cd "$(dirname "$0")/.."
. "${ENV_FILE:-./env.sh}"
ref=$1
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
pids=()
for h in $HOSTS; do
  ssh "$h" "cd $REPO_DIR && git fetch -q origin && git checkout -qf $ref && make deploy >&2 && git rev-parse HEAD" >"$tmp/$h" &
  pids+=($!)
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
[ $fail = 0 ] || { echo "deploy failed" >&2; exit 1; }
cat "$tmp/$APP_HOST"
