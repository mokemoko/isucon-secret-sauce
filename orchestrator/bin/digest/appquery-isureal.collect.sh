#!/usr/bin/env bash
# usage: appquery-isureal.collect.sh <pre|post> <host> <出力ディレクトリ>
# アプリ (Go、ISUREAL_QUERY_STATS=1) が localhost:6060/debug/querystats に出す「アプリから見たクエリの時間」(pgx の QueryTracer。
# ルーター越しの RTT・行の読み出しを含む) を、ベンチ前にリセットし、ベンチ後に <出力>/appquery-isureal.raw に取る。集計は appquery-isureal.sh。
# PPROF_HOSTS (アプリが動く台) 以外のホストでは何もしない (EXTRA_COLLECT_HOSTS を他の collect と共有するため)。
# アプリ側で無効 (404) なら何も置かない。APPQUERY_URL で URL を変えられる
set -euo pipefail
phase=$1 host=$2 out=$3
case " ${PPROF_HOSTS:-${APP_HOST:-}} " in *" $host "*) ;; *) exit 0 ;; esac
url=${APPQUERY_URL:-http://localhost:6060/debug/querystats}
case $phase in
  pre) ssh "$host" "curl -fsS '$url?reset=1' >/dev/null 2>&1 || true" ;;
  post) mkdir -p "$out"
    ssh "$host" "curl -fsS '$url'" >"$out/appquery-isureal.raw" 2>/dev/null || rm -f "$out/appquery-isureal.raw" ;;
  *) echo "usage: $0 <pre|post> <host> <dir>" >&2; exit 2 ;;
esac
