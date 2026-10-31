#!/usr/bin/env bash
# usage: bin/deploy.sh <ref>
# 2段で deploy し、APP_HOST にデプロイした sha を出力する
#   1. 全ホストで並列に fetch (GitHub の ssh 認証が時々失敗するので、1台ごとに FETCH_RETRY_WAIT の秒数をあけて再試行) し、ref があるかを確かめる。
#      1台でも失敗したら、どのホストも checkout せずに終わる (台ごとに版がずれて本番が壊れるのを防ぐ)
#   2. 全ホストで並列に checkout → make deploy。失敗したホストは「deploy failed (make deploy: <host>)」に出る (この場合は台ごとに版がずれている)
set -euo pipefail
cd "$(dirname "$0")/.."
. "${ENV_FILE:-./env.sh}"
ref=$1
wait_s=${FETCH_RETRY_WAIT:-2 5}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# <段の名前> <リモートのコマンド>: 全ホストで並列に実行し、失敗したホストがあれば deploy failed で終わる
run_all() {
  local stage=$1 cmd=$2 h failed=() pids=() hs=()
  for h in $HOSTS; do
    ssh "$h" "$cmd" >"$tmp/$h" &
    pids+=($!); hs+=("$h")
  done
  for i in "${!pids[@]}"; do wait "${pids[$i]}" || failed+=("${hs[$i]}"); done
  [ ${#failed[@]} = 0 ] || { echo "deploy failed ($stage: ${failed[*]})" >&2; exit 1; }
}

run_all fetch "cd $REPO_DIR && for w in $wait_s ''; do git fetch -q origin && break; [ -n \"\$w\" ] || exit 1; sleep \$w; done && git rev-parse -q --verify '$ref^{commit}' >/dev/null"
run_all "make deploy" "cd $REPO_DIR && git checkout -qf $ref && make deploy >&2 && git rev-parse HEAD"
cat "$tmp/$APP_HOST"
