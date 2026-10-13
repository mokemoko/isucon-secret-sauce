#!/usr/bin/env bash
# usage: bin/deploy-key.sh <owner/repo>   (人間が開始直後に1回実行する。RUNBOOK)
# env.sh の HOSTS の各台で鍵を作り、競技リポジトリに書き込み可の deploy key として登録し、GitHub に ssh できることを確かめる。
# リポジトリへの書き込み権限を渡す操作なので、エージェントに実行させると auto モードで止まる (リハ#2)。再実行してよい (登録済みの鍵は飛ばす)
set -euo pipefail
cd "$(dirname "$0")/.."
repo=${1:?usage: deploy-key.sh <owner/repo>}
. "${ENV_FILE:-./env.sh}"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
for h in $HOSTS; do
  ssh "$h" 'test -f ~/.ssh/id_ed25519 || ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519; cat ~/.ssh/id_ed25519.pub' >"$t/$h.pub"
  if gh repo deploy-key list -R "$repo" --json key -q '.[].key' | grep -qF "$(cut -d' ' -f1,2 "$t/$h.pub")"; then
    echo "$h: 登録済み"
  else
    gh repo deploy-key add "$t/$h.pub" -R "$repo" --allow-write -t "$h" >/dev/null && echo "$h: 登録"
  fi
  ssh "$h" 'grep -q "^github.com " ~/.ssh/known_hosts 2>/dev/null || ssh-keyscan -t ed25519 github.com >>~/.ssh/known_hosts 2>/dev/null; ssh -T git@github.com 2>&1 | head -1'
done
