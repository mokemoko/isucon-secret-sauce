#!/usr/bin/env bash
# usage: guard-journal.collect.sh <pre|post> <host> <出力ディレクトリ>
# BAN を行う常駐 (isureal-guard。アプリのアクションログを journald から読み、閾値を超えた IP を ip_bans に書く) の
# ログのうちベンチ中の行 (banned / ban failed / stats) を <出力>/guard-journal.raw に取る。集計は guard-journal.sh。
# pre はホストの時刻を <出力>/guard-journal.since に置く。GUARD_UNIT (既定 isureal-guard)。
# GUARD_HOSTS (既定 PPROF_HOSTS = アプリの台) 以外と、ユニットが動いていないホストでは何もしない
set -euo pipefail
phase=$1 host=$2 out=$3
case " ${GUARD_HOSTS:-${PPROF_HOSTS:-${APP_HOST:-}}} " in *" $host "*) ;; *) exit 0 ;; esac
unit=${GUARD_UNIT:-isureal-guard}
mkdir -p "$out"
case $phase in
  pre) ssh "$host" "systemctl is-active -q $unit && date +%s || true" >"$out/guard-journal.since"
    [ -s "$out/guard-journal.since" ] || rm -f "$out/guard-journal.since" ;;
  post) [ -s "$out/guard-journal.since" ] || exit 0
    ssh "$host" "sudo journalctl -u $unit --since @$(cat "$out/guard-journal.since") -o cat --no-pager | grep -E '^(banned|ban failed|stats):' || true" >"$out/guard-journal.raw" ;;
  *) echo "usage: $0 <pre|post> <host> <dir>" >&2; exit 2 ;;
esac
