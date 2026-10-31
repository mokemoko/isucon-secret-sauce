#!/usr/bin/env bash
# portal-bench.sh: 偽の orca (ブラウザの eval) で、実行依頼 → 状態の確認 → 結果の JSON までを確かめる
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# protobuf の応答を作る (field 番号は isuxportal の定義)
cat >"$t/enc.py" <<'PY'
import base64, sys
def v(n):
    a = b""
    while n > 127: a += bytes([(n & 127) | 128]); n >>= 7
    return a + bytes([n])
def f(no, x):
    if isinstance(x, int): return v(no << 3) + v(x)
    if isinstance(x, str): x = x.encode()
    return v(no << 3 | 2) + v(len(x)) + x
kind = sys.argv[1]
if kind == "job":
    st, passed, score = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    res = f(1, 1) + f(2, passed) + f(3, score) + f(4, f(1, score + 5) + f(2, 5)) + f(5, f(2, "load ok\nERROR: 1 件のエラー") + f(3, "debug"))
    job = f(1, 42) + f(3, 7) + f(4, st) + (f(18, res) if st == 4 else b"")
    print(base64.b64encode(f(1, job)).decode())
elif kind == "session":
    print(base64.b64encode(f(5, f(7, 7) + f(3, 1) + f(4, "203.0.113.1") + f(5, "10.0.0.1") + f(6, 4))).decode())
elif kind == "error":
    print(base64.b64encode(f(1, 400) + f(2, "Bad") + f(3, "既にジョブがあります")).decode())
PY
mkdir "$t/bin"
cat >"$t/bin/orca" <<EOF
#!/usr/bin/env bash
expr=\$5; echo "\$expr" >>"$t/calls"
reply() { jq -cn --arg r "{\"status\":\$1,\"b64\":\"\$2\"}" '{ok:true,result:{result:\$r}}'; }
case \$expr in
  *'"POST","/api/contestant/benchmark_jobs",[8,7]'*)
    if [ ! -e "$t/rejected" ] && [ -e "$t/reject-once" ]; then touch "$t/rejected"; reply 400 "\$(python3 $t/enc.py error)"; else reply 200 "\$(python3 $t/enc.py job 0 0 0)"; fi ;;
  *'"GET","/api/contestant/benchmark_jobs/42"'*)
    n=\$(grep -c 'benchmark_jobs/42' "$t/calls")
    if [ "\$n" -lt 2 ]; then reply 200 "\$(python3 $t/enc.py job 1 0 0)"; else reply 200 "\$(python3 $t/enc.py job 4 1 1234)"; fi ;;
  *'"GET","/api/session"'*) reply 200 "\$(python3 $t/enc.py session)" ;;
  *) reply 500 "" ;;
esac
EOF
chmod +x "$t/bin/orca"
export ORCA="$t/bin/orca" PORTAL_PAGE=p PORTAL_TARGET_ID=7 PORTAL_POLL_SEC=0

# 1) targets
[ "$("$root/bin/portal-bench.sh" targets)" = '{"id":7,"number":1,"public_ip":"203.0.113.1","private_ip":"10.0.0.1","status":4}' ] || { echo "FAIL targets"; exit 1; }

# 2) 実行依頼 → RUNNING → FINISHED。ベンチの出力と最終行の JSON
out=$("$root/bin/portal-bench.sh" 2>"$t/err")
echo "$out" | grep -q '^ERROR: 1 件のエラー$' || { echo "FAIL stdout: $out"; exit 1; }
[ "$(echo "$out" | tail -n1)" = '{"pass":true,"score":1234,"raw":1239,"deduction":5,"job_id":42,"status":"FINISHED","reason":""}' ] || { echo "FAIL result: $out"; exit 1; }
grep -q 'job 42: RUNNING' "$t/err" && grep -q 'job 42: FINISHED' "$t/err" && grep -q '^debug$' "$t/err" || { echo "FAIL stderr"; cat "$t/err"; exit 1; }

# 3) 1回目の実行依頼が断られても、やり直して通る (待ちは sleep を差し替えて飛ばす)
: >"$t/calls"; touch "$t/reject-once"
printf '#!/bin/sh\nexit 0\n' >"$t/bin/sleep"; chmod +x "$t/bin/sleep"
out=$(PATH="$t/bin:$PATH" "$root/bin/portal-bench.sh" 2>"$t/err")
grep -q 'enqueue: HTTP 400 Bad 既にジョブがあります (1/30)' "$t/err" && [ "$(echo "$out" | tail -n1 | jq -r .score)" = 1234 ] || { echo "FAIL retry"; cat "$t/err"; exit 1; }
echo ok
