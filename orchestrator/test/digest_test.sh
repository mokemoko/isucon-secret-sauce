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
ENV_FILE="$t/env.sh" "$root/bin/digest.sh" "$t/st/analysis/b1"
got=$(jq -c 'map(.weight)' "$t/st/analysis/b1/h1/endpoints.json")
[ "$got" = '[1,null,0.5,null]' ] || { echo "FAIL weights: $got"; exit 1; }
grep -q '加点あり (weight>0) の時間比率 60%' "$t/st/analysis/b1/summary.md" || { echo "FAIL weighted share"; cat "$t/st/analysis/b1/summary.md"; exit 1; }

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
