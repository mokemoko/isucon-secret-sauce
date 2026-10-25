#!/usr/bin/env bash
# usage: dns-pdns.collect.sh <pre|post> <host> <出力ディレクトリ>
# PowerDNS の統計 API (カウンタは起動からの累積) をベンチ前後に取り、<出力>/dns-pdns.{pre,post}.json に置く。差分は dns-pdns.sh が取る。
# env.sh の PDNS_API_KEY (必須。サーバの pdns.conf の api-key) と PDNS_API_URL (既定 http://127.0.0.1:8081。サーバ上から見た URL)
set -euo pipefail
phase=$1 host=$2 out=$3
case $phase in pre|post) ;; *) echo "usage: $0 <pre|post> <host> <dir>" >&2; exit 2 ;; esac
mkdir -p "$out"
: "${PDNS_API_KEY:?env.sh に PDNS_API_KEY (pdns.conf の api-key) を書く}"
ssh "$host" "curl -fsS -H 'X-API-Key: $PDNS_API_KEY' ${PDNS_API_URL:-http://127.0.0.1:8081}/api/v1/servers/localhost/statistics" >"$out/dns-pdns.$phase.json"
