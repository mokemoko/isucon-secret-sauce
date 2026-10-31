#!/usr/bin/env bash
# usage: pgact-sampler.collect.sh <pre|post> <host> <出力ディレクトリ>
# PostgreSQL のベンチ中の様子を取る。DB_HOSTS 以外のホストでは何もしない。集計は pgact-sampler.sh → <host>/pgact.json
#  - セッションのサンプリング: pre で DB ホストに pgact-sampler.remote.sh を置いて切り離して動かし、PGACT_INTERVAL 秒 (既定 0.5) ごとに
#    pg_stat_activity の idle 以外のクライアントを1行ずつ書く。待ち (wait_event)、ロック待ちならブロックしている pid の文と状態。
#    post で止めて <出力>/pgact-sampler.raw に取る (タブ区切り)
#      T <epoch>                                       (1回ごと)
#      S <pid> <state> <wait_event_type> <wait_event> <query> <blocking pids> <blocker の query> <blocker の state>
#    blocker の query は「その時点で実行中、または idle in transaction なら最後に実行した文」(ロックを取った文とは限らない)
#  - テーブル・I/O の統計: pg_statio_user_tables と pg_stat_io の pre/post (<出力>/pgact-sampler.{pre,post}.tsv)。差分は adapter
# PSQL_CMD (既定 "sudo -u postgres psql -X") はサーバ上で superuser の psql を起動するコマンド (-d <db> を足してよい。シングルクォートを含めない)
set -euo pipefail
phase=$1 host=$2 out=$3
case " ${DB_HOSTS:-} " in *" $host "*) ;; *) exit 0 ;; esac
p=${PSQL_CMD:-sudo -u postgres psql -X}
mkdir -p "$out"
stop='f=/tmp/isu-pgact.pid; [ -f $f ] && sudo kill -TERM -- -$(cat $f) 2>/dev/null; rm -f $f; true'
stats() {
  ssh "$host" "$p -q -A -t -F \$'\\t'" <<'SQL'
SELECT 'R', schemaname || '.' || relname, heap_blks_read, heap_blks_hit, coalesce(idx_blks_read, 0), coalesce(idx_blks_hit, 0),
  coalesce(toast_blks_read, 0), coalesce(toast_blks_hit, 0), coalesce(tidx_blks_read, 0), coalesce(tidx_blks_hit, 0)
FROM pg_statio_user_tables;
SELECT 'I', backend_type, object, context, coalesce(reads, 0), coalesce(read_time, 0), coalesce(writes, 0), coalesce(hits, 0), coalesce(op_bytes, 8192)
FROM pg_stat_io WHERE coalesce(reads, 0) + coalesce(writes, 0) + coalesce(hits, 0) > 0;
SQL
}
case $phase in
  pre)
    stats >"$out/pgact-sampler.pre.tsv"
    # 前回の残りを止めてから置く。setsid で切り離したプロセスグループ (pid ファイルの値) ごと止める
    ssh "$host" "$stop; cat >/tmp/isu-pgact.sh" <"$(dirname "$0")/pgact-sampler.remote.sh"
    ssh "$host" "PGACT_INTERVAL='${PGACT_INTERVAL:-0.5}' PGACT_PSQL='$p' setsid nohup timeout 1800 bash /tmp/isu-pgact.sh </dev/null >/tmp/isu-pgact.out 2>/dev/null & echo \$! >/tmp/isu-pgact.pid"
    ;;
  post)
    ssh "$host" "$stop; sleep 1; cat /tmp/isu-pgact.out" >"$out/pgact-sampler.raw" || true
    stats >"$out/pgact-sampler.post.tsv"
    ;;
  *) echo "usage: $0 <pre|post> <host> <dir>" >&2; exit 2 ;;
esac
