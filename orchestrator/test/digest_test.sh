#!/usr/bin/env bash
# digest アダプタの確認
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# resources-proc: 2コア・1秒間隔で、全体 400 tick 中 user 100 / system 40、
# mysqld は2プロセス合算で 60 tick (=60%/1コア)、終了したプロセスと新しいプロセスは数えない
cat >"$t/res.raw" <<'R'
H ncpu=2 clk=100 page=4096
T 1000
cpu 1000 0 500 8000 10 0 0 0
M 1000 800
N 0 0
D 0 0
P 1 mysqld 100 256
P 2 mysqld 50 256
P 3 gone 10 1
T 2000
cpu 1100 0 540 8240 30 0 0 0
M 1000 600
N 1048576 2097152
D 2048 0
P 1 mysqld 140 256
P 2 mysqld 70 256
P 4 new_proc 500 1
R
r=$("$root/bin/digest/resources-proc.sh" "$t/res.raw" "$t/res.txt")
exp='{"ncpu":2,"user":[25],"sys":[10],"iowait":[5],"mem":[40],"rx":[1048576],"tx":[2097152],"rd":[1048576],"mysqld":[60],"rss":[2],"new":[0]}'
got=$(echo "$r" | jq -c '{ncpu, user: .host.user, sys: .host.sys, iowait: .host.iowait, mem: .host.mem, rx: .host.rx, tx: .host.tx, rd: .host.rd,
  mysqld: (.procs[] | select(.comm == "mysqld") | .cpu), rss: (.procs[] | select(.comm == "mysqld") | .rss), new: (.procs[] | select(.comm == "new_proc") | .cpu)} | walk(if type == "number" then . + 0 else . end)')
[ "$got" = "$exp" ] || { echo "FAIL resources: $got"; exit 1; }

# query-psdigest: mysql -B のエスケープ (\n \t \\) を戻し、ピコ秒を秒に、合計/回数を1回あたりにする
printf '%s\t' 'SELECT * FROM `posts` WHERE `user_id` = ?' 4 2000000000000 500000000000 900000000000 800000000000 400 8 4 0 1 0 >"$t/psd.raw"
printf '%s\n' 'SELECT * FROM posts WHERE body = '"'"'a\nb\\c'"'"'' >>"$t/psd.raw"
printf 'SELECT 1\t1\t1\t1\t1\t1\t0\t1\t0\t0\t0\t0\tNULL\n' >>"$t/psd.raw"
r=$("$root/bin/digest/query-psdigest.sh" "$t/psd.raw" "$t/psd.txt")
got=$(echo "$r" | jq -c '.[0] | {fingerprint, count, sum, avg, p95, max, rows_examined_avg, rows_sent_avg, no_index_used, tmp_disk_tables, sample} | walk(if type == "number" then . + 0 else . end)')
exp='{"fingerprint":"SELECT * FROM `posts` WHERE `user_id` = ?","count":4,"sum":2,"avg":0.5,"p95":0.8,"max":0.9,"rows_examined_avg":100,"rows_sent_avg":2,"no_index_used":4,"tmp_disk_tables":1,"sample":"SELECT * FROM posts WHERE body = '"'"'a\nb\\c'"'"'"}'
[ "$got" = "$exp" ] || { echo "FAIL psdigest: $got"; exit 1; }
[ "$(echo "$r" | jq -r '.[1].sample')" = "" ] || { echo "FAIL psdigest NULL sample"; exit 1; }

# query-pgss: ミリ秒を秒に、p95 は mean + 2*stddev、ヒット率
printf 'SELECT * FROM posts WHERE id = $1\t100\t2500\t25\t300\t10\t100\t900\t100\n' >"$t/pgss.raw"
got=$("$root/bin/digest/query-pgss.sh" "$t/pgss.raw" "$t/pgss.txt" | jq -c '.[0] | {count, sum, avg, p95, max, rows_examined_avg, rows_sent_avg, hit_ratio}')
[ "$got" = '{"count":100,"sum":2.5,"avg":0.025,"p95":0.045,"max":0.3,"rows_examined_avg":null,"rows_sent_avg":1,"hit_ratio":0.9}' ] || { echo "FAIL pgss: $got"; exit 1; }

# 採点の重み: 完全一致・^ 始まりの正規表現 (alp がまとめた uri にも当たる)・method "*"・不正な正規表現・未記載は null
mkdir -p "$t/st/docs" "$t/st/analysis/b1/h1"; : >"$t/env.sh"
cat >"$t/st/analysis/b1/h1/endpoints.json" <<'J'
[{"method":"GET","uri":"/","count":1,"status":{"4xx":0,"5xx":0},"sum":4,"avg":1,"p99":1},
 {"method":"GET","uri":"/posts","count":1,"status":{"4xx":0,"5xx":0},"sum":3,"avg":1,"p99":1},
 {"method":"GET","uri":"^/image/\\d+$","count":1,"status":{"4xx":0,"5xx":0},"sum":2,"avg":1,"p99":1},
 {"method":"POST","uri":"/","count":1,"status":{"4xx":0,"5xx":0},"sum":1,"avg":1,"p99":1}]
J
cat >"$t/st/docs/scoring.json" <<'J'
{"endpoints":[{"method":"GET","uri":"/","weight":1},{"method":"*","uri":"^/image/","weight":0.5},{"method":"POST","uri":"^/[","weight":9}]}
J
printf '%s\n' 'level=INFO msg=start' 'level=WARN msg=mismatch CODE=33' 'level=ERROR msg=timeout' 'level=WARN msg=mismatch CODE=33' >"$t/st/analysis/b1/bench.txt"
ENV_FILE="$t/env.sh" "$root/bin/digest.sh" "$t/st/analysis/b1"
[ "$(wc -l <"$t/st/analysis/b1/warnings.txt" | tr -d ' ')" = 3 ] || { echo "FAIL warnings.txt"; exit 1; }
grep -q '^warnings=3 ' "$t/st/analysis/b1/summary.md" || { echo "FAIL warnings in summary"; cat "$t/st/analysis/b1/summary.md"; exit 1; }
echo 'BENCH_WARN_RE="CODE=33"' >"$t/env2.sh"
ENV_FILE="$t/env2.sh" "$root/bin/digest.sh" "$t/st/analysis/b1"
grep -q '^warnings=2 ' "$t/st/analysis/b1/summary.md" || { echo "FAIL BENCH_WARN_RE"; exit 1; }
# 減点の件数: 最後に当たった行の最初の整数。BENCH_PENALTY_RE が無ければ penalty.txt を作らない
printf '%s\n' 'Errors: 2 (critical 0)' 'level=WARN x' 'Errors: 5 (critical 1)' >>"$t/st/analysis/b1/bench.txt"
printf '%s\n' 'BENCH_PENALTY_RE="Errors: [0-9]+"' >"$t/env3.sh"
ENV_FILE="$t/env3.sh" "$root/bin/digest.sh" "$t/st/analysis/b1"
[ "$(cat "$t/st/analysis/b1/penalty.txt")" = 5 ] && grep -q '^penalty=5 ' "$t/st/analysis/b1/summary.md" || { echo "FAIL penalty"; cat "$t/st/analysis/b1/summary.md"; exit 1; }
ENV_FILE="$t/env2.sh" "$root/bin/digest.sh" "$t/st/analysis/b1"
[ ! -f "$t/st/analysis/b1/penalty.txt" ] || { echo "FAIL penalty.txt without RE"; exit 1; }
ENV_FILE="$t/env.sh" "$root/bin/digest.sh" "$t/st/analysis/b1"
got=$(jq -c 'map(.weight)' "$t/st/analysis/b1/h1/endpoints.json")
[ "$got" = '[1,null,0.5,null]' ] || { echo "FAIL weights: $got"; exit 1; }
grep -q '加点あり (weight>0) の時間比率 60%' "$t/st/analysis/b1/summary.md" || { echo "FAIL weighted share"; cat "$t/st/analysis/b1/summary.md"; exit 1; }

# dns-pdns: カウンタは前後の差分、latency は post の値。pre より uptime が小さければ再起動とみなし post の累積を使う
st() { printf '[{"name":"udp-queries","type":"StatisticItem","value":"%s"},{"name":"tcp-queries","type":"StatisticItem","value":"0"},{"name":"backend-queries","type":"StatisticItem","value":"%s"},{"name":"user-msec","type":"StatisticItem","value":"%s"},{"name":"uptime","type":"StatisticItem","value":"%s"},{"name":"latency","type":"StatisticItem","value":"%s"},{"name":"response-by-qtype","type":"MapStatisticItem","value":[]}]' "$@"; }
mkdir -p "$t/dns"; st 100 400 1000 50 9 >"$t/dns/dns-pdns.pre.json"; st 1100 4400 3500 150 777 >"$t/dns/dns-pdns.post.json"
got=$("$root/bin/digest/dns-pdns.sh" "$t/dns/dns-pdns.post.json" "$t/dns/raw.json" | jq -c '{sec, restarted, q: .queries, b: .backend_queries, u: .cpu_sec.user, l: .latency_us.all, nx: .rcode.nxdomain}')
[ "$got" = '{"sec":100,"restarted":false,"q":{"udp":1000,"tcp":0},"b":4000,"u":2.5,"l":777,"nx":null}' ] || { echo "FAIL dns-pdns: $got"; exit 1; }
st 100 400 1000 10 9 >"$t/dns/dns-pdns.post.json"; st 5000 1 1 900 1 >"$t/dns/dns-pdns.pre.json"
[ "$("$root/bin/digest/dns-pdns.sh" "$t/dns/dns-pdns.post.json" "$t/dns/raw.json" | jq -c '[.restarted, .sec, .queries.udp]')" = '[true,10,100]' ] || { echo "FAIL dns-pdns restart"; exit 1; }

# extcmd-jsonl: cmd ごとの集計。JSON でない行・cmd の無い行は捨てる
printf '%s\n' '{"cmd":"a","sec":0.1,"err":false}' '{"cmd":"a","sec":0.3,"err":true}' 'not json' '{"x":1}' '{"cmd":"b","sec":1}' >"$t/ext.log"
got=$("$root/bin/digest/extcmd-jsonl.sh" "$t/ext.log" "$t/ext.txt" | jq -c 'map([.cmd, .count, .errors, (.sum * 10 | round), .p95, .max])')
[ "$got" = '[["b",1,0,10,1,1],["a",2,1,4,0.3,0.3]]' ] || { echo "FAIL extcmd: $got"; exit 1; }

# guard-journal: banned の行数・IP の異なり数・理由別、stats は最初と最後の累積の差
printf '%s\n' 'stats: lines=10 action_logs=5 failures=2 bans=0' 'banned: ip=1.2.3.4 reason=login failures=10 window=10s' \
  'banned: ip=1.2.3.4 reason=login failures=10 window=10s' 'ban failed: ip=9.9.9.9 reason=login: x' \
  'banned: ip=5.6.7.8 reason=invalid_signature failures=3 window=5s' 'stats: lines=110 action_logs=85 failures=22 bans=3' >"$t/guard.raw"
got=$("$root/bin/digest/guard-journal.sh" "$t/guard.raw" "$t/guard.txt" | jq -c .)
[ "$got" = '{"bans":3,"ban_failed":1,"ips":2,"by_reason":{"invalid_signature":1,"login":2},"stats":{"lines":100,"action_logs":80,"failures":20,"bans":3}}' ] || { echo "FAIL guard: $got"; exit 1; }

# appquery-isureal: routes は db_sum 降順、queries は sum 降順
echo '{"sec":1,"pool":{"wait_count":0},"routes":[{"route":"a","db_sum":1},{"route":"b","db_sum":2}],"queries":[{"query":"x","sum":1},{"query":"y","sum":3}]}' >"$t/aq.raw"
got=$("$root/bin/digest/appquery-isureal.sh" "$t/aq.raw" "$t/aq.txt" | jq -c '[.routes[].route, .queries[].query]')
[ "$got" = '["b","a","y","x"]' ] || { echo "FAIL appquery: $got"; exit 1; }

# pgact-sampler: 2回のサンプルで1回あたりの本数、ロック待ちの組、テーブルの差分 (パーティションをまとめる、MB)、pg_stat_io の差分
mkdir -p "$t/pga"
printf 'T\t100.0\nS\t1\tactive\tLock\ttransactionid\tUPDATE w SET x=1\t{2}\tSELECT 1 FOR UPDATE\tidle in transaction\nS\t2\tidle in transaction\tClient\tClientRead\tSELECT 1 FOR UPDATE\t{}\t\t\nT\t100.5\nS\t1\tactive\tLock\ttransactionid\tUPDATE w SET x=1\t{2}\tSELECT 1 FOR UPDATE\tidle in transaction\n' >"$t/pga/pgact-sampler.raw"
printf 'R\tpublic.img_202601\t0\t0\t0\t0\t0\t0\t0\t0\nR\tpublic.img_202602\t0\t0\t0\t0\t0\t0\t0\t0\nI\tclient backend\trelation\tnormal\t0\t0\t0\t0\t8192\n' >"$t/pga/pgact-sampler.pre.tsv"
printf 'R\tpublic.img_202601\t128\t0\t0\t0\t64\t0\t0\t0\nR\tpublic.img_202602\t0\t0\t0\t0\t64\t128\t0\t0\nI\tclient backend\trelation\tnormal\t256\t5.5\t0\t128\t8192\n' >"$t/pga/pgact-sampler.post.tsv"
r=$("$root/bin/digest/pgact-sampler.sh" "$t/pga/pgact-sampler.raw" "$t/pga/raw.txt")
got=$(echo "$r" | jq -c '[.ticks, .sec, .active_avg, (.waits | map([.state, .wait, .sessions])), (.lock_waits | map([.waiting, .blocker, .blocker_state, .samples])), .tables, (.io | map([.context, .read_mb, .read_ms, .hit_mb]))] | walk(if type == "number" then . + 0 else . end)')
exp='[2,0.5,1.5,[["active","Lock:transactionid",1],["idle in transaction","Client:ClientRead",0.5]],[["UPDATE w SET x=1","SELECT 1 FOR UPDATE","idle in transaction",2]],[{"table":"public.img","read_mb":2,"hit_mb":1,"heap_read_mb":1,"toast_read_mb":1,"idx_read_mb":0}],[["normal",2,6,1]]]'
[ "$got" = "$exp" ] || { echo "FAIL pgact: $got"; exit 1; }

# digest.sh: appquery / guard / pgact の raw から <host>/<kind>.json と summary.md の節を作る
mkdir -p "$t/st/analysis/b2/h1" "$t/st/analysis/b2/db"
cp "$t/aq.raw" "$t/st/analysis/b2/h1/appquery-isureal.raw"; cp "$t/guard.raw" "$t/st/analysis/b2/h1/guard-journal.raw"; cp "$t/pga"/pgact-sampler.* "$t/st/analysis/b2/db/"
ENV_FILE="$t/env.sh" "$root/bin/digest.sh" "$t/st/analysis/b2" >/dev/null 2>&1 || true
for f in h1/appquery.json h1/guard.json db/pgact.json; do [ -s "$t/st/analysis/b2/$f" ] || { echo "FAIL digest $f: $(cat "$t/st/analysis/b2/digest.err" 2>/dev/null)"; exit 1; }; done
for h in '## appquery h1' '## guard h1' '## pgact db'; do grep -q "^$h" "$t/st/analysis/b2/summary.md" || { echo "FAIL summary $h"; exit 1; }; done
grep -q '^2 Lock:transactionid UPDATE w SET x=1 <= (idle in transaction) SELECT 1 FOR UPDATE' "$t/st/analysis/b2/summary.md" || { echo "FAIL summary lock_waits"; exit 1; }

command -v pt-query-digest >/dev/null || { echo "ok (pt-query-digest なしのため query-pt は skip)"; exit 0; }
# query-pt: fingerprint の英字が残り、制御文字と長さが抑えられること
cols=$(seq -f 'column_%g' 1 100 | paste -sd, -)   # fingerprint 自体が 500 文字を超えるクエリ
q() { printf '# Time: 2026-10-12T00:00:00.000000Z\n# User@Host: u[u] @ localhost []  Id: 1\n# Query_time: %s  Lock_time: 0.000000 Rows_sent: 1  Rows_examined: 10\nSET timestamp=1;\n%s;\n' "$1" "$2"; }
{
  q 0.5 'SELECT * FROM users WHERE id = 1'
  q 0.3 'SELECT * FROM users WHERE id = 2'
  q 0.1 "SELECT $cols FROM t WHERE c = '$(printf 'a\001\002b')'"
} >"$t/slow.log"
out=$("$root/bin/digest/query-pt.sh" "$t/slow.log" "$t/raw.txt")
[ "$(echo "$out" | jq -r '.[0].fingerprint')" = 'select * from users where id = ?' ] || { echo "FAIL fingerprint: $(echo "$out" | jq -c '.[0]')"; exit 1; }
[ "$(echo "$out" | jq '.[0].count')" = 2 ] || { echo "FAIL count"; exit 1; }
echo "$out" | jq -e 'all(.[].fingerprint; length <= 500 and (test("[\u0001-\u0008]") | not))' >/dev/null || { echo "FAIL long/control fingerprint"; exit 1; }
[ -s "$t/raw.txt" ] || { echo "FAIL raw output"; exit 1; }
echo ok
