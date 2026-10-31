#!/usr/bin/env bash
# 本番サーバのロック。ベンチ・deploy・再起動・本番での手作業を重ねないため、オーケストレータの外で作業する人も同じロックを使う
# ロックは LOCK_HOST (既定 APP_HOST) 上のディレクトリ LOCK_PATH (既定 /var/tmp/isucon-bench.lock)。mkdir で取り、中の owner に
# 「トークン 取得時刻(epoch) 誰が 何を」を書く。/var/tmp は再起動で消えないので、restart-check.sh の再起動をまたいで持てる
# usage:
#   bin/lock.sh acquire <何をするか>   空くまで待って取り、トークンを標準出力に出す (待つ間は30秒ごとに持ち主を標準エラーに出す)
#   bin/lock.sh release <トークン>     自分のトークンのときだけ離す
#   bin/lock.sh status [--json]        free か「held <経過秒> <誰が 何を>」
#   bin/lock.sh break                  持ち主に関係なく消す (人間が、持ち主の作業が終わっていることを確かめてから)
# env.sh が無くても LOCK_HOST=isu1 を渡せば使える (オーケストレータの外の人向け)
set -uo pipefail
cd "$(dirname "$0")/.."
f=${ENV_FILE:-./env.sh}; [ -f "$f" ] && . "$f"
H=${LOCK_HOST:-${APP_HOST:-}}; P=${LOCK_PATH:-/var/tmp/isucon-bench.lock}
[ -n "$H" ] || { echo "lock.sh: LOCK_HOST か env.sh の APP_HOST が要る" >&2; exit 2; }
rs() { ssh -o ConnectTimeout=5 "$H" "$@"; }

# 持ち主の行 (無ければ free)。ssh できなければ失敗
owner() { rs "if [ -d '$P' ]; then cat '$P/owner' 2>/dev/null || echo '- 0 (owner 無し)'; else echo free; fi" </dev/null; }

case ${1:-} in
  acquire)
    tok=$(hostname -s)-$$-$RANDOM$RANDOM
    line="$tok $(date +%s) ${LOCK_WHO:-$(id -un)@$(hostname -s)} ${2:-}"
    n=0
    until printf '%s\n' "$line" | rs "mkdir '$P' 2>/dev/null && cat >'$P/owner'"; do
      [ $((n % 15)) = 0 ] && echo "lock.sh: 待機中 ($(owner 2>/dev/null | cut -d' ' -f3- || echo "$H に ssh できない"))" >&2
      n=$((n + 1)); sleep 2
    done
    echo "$tok" ;;
  release)
    tok=${2:?usage: lock.sh release <トークン>}
    for _ in 1 2 3; do
      r=$(rs "o=\$(cut -d' ' -f1 '$P/owner' 2>/dev/null); if [ \"\$o\" = '$tok' ]; then rm -rf '$P' && echo ok; else echo \"other \$o\"; fi" </dev/null) && break
      sleep 2
    done
    case ${r:-} in
      ok) ;;
      other*) echo "lock.sh: 自分のロックではないので離さない (持ち主 ${r#other })" >&2 ;;
      *) echo "lock.sh: $H に ssh できず、ロックを離せなかった。lock.sh status で確かめる" >&2; exit 1 ;;
    esac ;;
  status)
    o=$(owner) || { echo "lock.sh: $H に ssh できない" >&2; exit 1; }
    if [ "$o" = free ]; then
      [ "${2:-}" = --json ] && echo '{"held":false}' || echo free
    else
      t=$(echo "$o" | cut -d' ' -f2); who=$(echo "$o" | cut -d' ' -f3-)
      age=$(( $(date +%s) - ${t:-0} ))
      [ "${2:-}" = --json ] && jq -cn --argjson age "$age" --arg who "$who" '{held: true, age_sec: $age, who: $who}' || echo "held ${age}s $who"
    fi ;;
  break)
    rs "rm -rf '$P'" </dev/null ;;
  *) sed -n '2,9p' "$0" >&2; exit 2 ;;
esac
