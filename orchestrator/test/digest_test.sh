#!/usr/bin/env bash
# digest アダプタの確認 (pt-query-digest が無ければ skip)。fingerprint の英字が残り、制御文字と長さが抑えられること
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
command -v pt-query-digest >/dev/null || { echo "skip: pt-query-digest なし"; exit 0; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
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
