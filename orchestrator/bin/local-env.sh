#!/usr/bin/env bash
# usage: bin/local-env.sh <name> [dir]   (worktree の直下で実行。dir の既定は local)
# worktree ごとのローカル環境の値を <dir>/.env に固定する。docker compose は compose ファイルと同じ場所の .env を自動で読む。
# Bash の呼び出しごとにシェルが新しくなるので export は残らない。ポートを手で打つと他の worktree に送ってしまう (リハ#2)
#   COMPOSE_PROJECT_NAME=<name を小文字・英数と - _ にしたもの>
#   LOCAL_PORT=P (nginx)  LOCAL_DB_PORT=P+1 (DB)  LOCAL_EXTRA_PORT=P+2 (その他)。P は name から決め、使用中なら 10 ずつずらす (20000〜59990)
# 既に .env があれば書き換えずに中身を出す (冪等)。.env は git の除外に足す
set -euo pipefail
name=${1:?usage: local-env.sh <name> [dir]}; dir=${2:-local}
f=$dir/.env
mkdir -p "$dir"
if [ ! -f "$f" ]; then
  used() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
  p=$(( 20000 + $(printf %s "$name" | cksum | cut -d' ' -f1) % 4000 * 10 ))
  while used $p || used $((p + 1)) || used $((p + 2)); do p=$(( p + 10 > 59990 ? 20000 : p + 10 )); done
  printf 'COMPOSE_PROJECT_NAME=%s\nLOCAL_PORT=%s\nLOCAL_DB_PORT=%s\nLOCAL_EXTRA_PORT=%s\n' \
    "$(printf %s "$name" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_-' '-')" $p $((p + 1)) $((p + 2)) >"$f"
fi
ex=$(git rev-parse --git-path info/exclude 2>/dev/null || true)
[ -z "$ex" ] || grep -qxF "/$f" "$ex" 2>/dev/null || { mkdir -p "$(dirname "$ex")"; echo "/$f" >>"$ex"; }
cat "$f"
