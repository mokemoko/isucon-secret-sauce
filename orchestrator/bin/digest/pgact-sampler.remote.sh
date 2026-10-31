#!/usr/bin/env bash
# pgact-sampler.collect.sh が DB ホストの /tmp/isu-pgact.sh に置いて setsid で動かすサンプラー (止め方: pkill -f isu-pgact.sh。timeout 1800 でも止まる)
# psql を1本だけ起動し、PGACT_INTERVAL 秒ごとに pg_stat_activity を問い合わせる (接続を張り直さない)。出力の形は pgact-sampler.collect.sh の冒頭
set -u
iv=${PGACT_INTERVAL:-0.5}
while :; do
  echo "SELECT 'T', extract(epoch FROM clock_timestamp());"
  echo "SELECT 'S', a.pid, a.state, coalesce(a.wait_event_type, ''), coalesce(a.wait_event, ''), left(regexp_replace(a.query, '\s+', ' ', 'g'), 300),
    pg_blocking_pids(a.pid)::text, coalesce(left(regexp_replace(b.query, '\s+', ' ', 'g'), 300), ''), coalesce(b.state, '')
    FROM pg_stat_activity a LEFT JOIN pg_stat_activity b ON b.pid = (pg_blocking_pids(a.pid))[1]
    WHERE a.backend_type = 'client backend' AND a.state <> 'idle' AND a.pid <> pg_backend_pid();"
  sleep "$iv"
done | ${PGACT_PSQL:-sudo -u postgres psql -X} -q -A -t -F $'\t'
