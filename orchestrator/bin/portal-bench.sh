#!/usr/bin/env bash
# usage: bin/portal-bench.sh            ポータル (isuxportal) でベンチを1回実行し、終わるまで待つ。BENCH_CMD に使う
#                                       標準出力: ベンチの出力 (警告・減点の行を BENCH_WARN_RE・BENCH_PENALTY_RE で拾える) と、最終行に {"pass","score","raw","deduction","job_id","status"}
#        bin/portal-bench.sh targets    負荷をかける先の候補 (サーバの id・番号・IP)。PORTAL_TARGET_ID が空なら先頭を使う (ポータルの Enqueue ボタンと同じ)
# Orca のブラウザで開いたポータルのタブ (PORTAL_PAGE。`orca tab list --worktree all --json` の browserPageId) の中で API を呼ぶ。
# ログインの Cookie と CSRF トークンはそのタブのものを使い、手元には持ち出さない。タブを閉じる・ログアウトすると動かない
set -euo pipefail
cd "$(dirname "$0")/.."
[ -n "${PORTAL_PAGE:-}" ] || . "${ENV_FILE:-./env.sh}"
: "${PORTAL_PAGE:?env.sh に PORTAL_PAGE (ポータルのタブの browserPageId) を書く}"
ORCA=${ORCA:-orca}
POLL=${PORTAL_POLL_SEC:-5}; TIMEOUT=${PORTAL_TIMEOUT_SEC:-900}; TRIES=${PORTAL_ENQUEUE_TRIES:-30}

# (method, path, protobuf の本文のバイト列 or null) → {"status":<HTTP>,"b64":<応答の本文>}
JS_CALL='async (m,p,body)=>{const h={Accept:"application/vnd.google.protobuf"};let tok=document.querySelector("meta[name=csrf-token]")?.content;if(!tok&&m!=="GET"){const html=await (await fetch("/contestant",{credentials:"same-origin"})).text();tok=(html.match(/name="csrf-token" content="([^"]+)"/)||[])[1]}if(tok)h["X-Csrf-Token"]=tok;if(body)h["Content-Type"]="application/vnd.google.protobuf";const r=await fetch(p,{method:m,headers:h,body:body?new Uint8Array(body):undefined,credentials:"same-origin"});const b=new Uint8Array(await r.arrayBuffer());let s="";for(const x of b)s+=String.fromCharCode(x);return JSON.stringify({status:r.status,b64:btoa(s)})}'
call() { "$ORCA" eval --page "$PORTAL_PAGE" --expression "($JS_CALL)(\"$1\",\"$2\",${3:-null})" --json | jq -er '.result.result'; }
proto() { python3 -I bin/portal-proto.py "$@"; }
errmsg() { proto error "$(echo "$1" | jq -r .b64)" 2>/dev/null | jq -r '"\(.name) \(.message)"' || echo "?"; }

if [ "${1:-}" = targets ]; then
  r=$(call GET /api/session)
  [ "$(echo "$r" | jq .status)" = 200 ] || { echo "session: HTTP $(echo "$r" | jq .status) $(errmsg "$r")" >&2; exit 1; }
  proto session "$(echo "$r" | jq -r .b64)" | jq -c '.[]'
  exit 0
fi

# 負荷をかける先。未設定ならポータルの Enqueue ボタンと同じく、サーバ一覧の先頭 (session の contestant_instances[0])
if [ -z "${PORTAL_TARGET_ID:-}" ]; then
  r=$(call GET /api/session)
  PORTAL_TARGET_ID=$(proto session "$(echo "$r" | jq -r .b64)" | jq -r '.[0].id // empty')
  [ -n "$PORTAL_TARGET_ID" ] || { echo '{"pass":false,"score":0,"error":"portal: サーバ一覧が空 (ログイン・サーバの登録を確かめる)"}'; exit 0; }
fi
# EnqueueBenchmarkJobRequest { int64 target_id = 1 }
body=$(python3 -I -c 'import sys
n=int(sys.argv[1]); a=[8]
while n>127: a.append((n&127)|128); n>>=7
a.append(n); print(a)' "$PORTAL_TARGET_ID" | tr -d ' ')

job_id=
for i in $(seq "$TRIES"); do
  r=$(call POST /api/contestant/benchmark_jobs "$body") || r='{"status":0,"b64":""}'
  st=$(echo "$r" | jq .status)
  if [ "$st" = 200 ]; then job_id=$(proto job "$(echo "$r" | jq -r .b64)" | jq -r .id); break; fi
  echo "enqueue: HTTP $st $(errmsg "$r") ($i/$TRIES)" >&2
  case $st in 401|403|404) echo '{"pass":false,"score":0,"error":"portal enqueue rejected (ログイン・競技時間・target を確かめる)"}'; exit 0 ;; esac
  sleep 10   # 前のジョブが残っている・一時的な失敗。少し待ってやり直す
done
[ -n "$job_id" ] && [ "$job_id" != 0 ] || { echo '{"pass":false,"score":0,"error":"portal enqueue failed"}'; exit 0; }
echo "job $job_id を実行依頼" >&2

start=$(date +%s); last=; fails=0
while :; do
  if r=$(call GET "/api/contestant/benchmark_jobs/$job_id") && [ "$(echo "$r" | jq .status)" = 200 ]; then
    fails=0; j=$(proto job "$(echo "$r" | jq -r .b64)"); s=$(echo "$j" | jq -r .status)
    [ "$s" = "$last" ] || { echo "job $job_id: $s" >&2; last=$s; }
    case $s in FINISHED|ERRORED|CANCELLED) break ;; esac
  else
    fails=$((fails + 1)); [ $fails -lt 10 ] || { echo "{\"pass\":false,\"score\":0,\"job_id\":$job_id,\"error\":\"portal poll failed\"}"; exit 0; }
  fi
  [ $(( $(date +%s) - start )) -lt "$TIMEOUT" ] || { echo "{\"pass\":false,\"score\":0,\"job_id\":$job_id,\"error\":\"portal timeout\"}"; exit 0; }
  sleep "$POLL"
done
echo "$j" | jq -r .stdout
echo "$j" | jq -r '.stderr' >&2
echo "$j" | jq -c '{pass:(.status == "FINISHED" and .passed), score, raw, deduction, job_id:.id, status, reason}'
