#!/bin/sh
# リハーサル用: ポータルの負荷走行の代わり。bench 専用ホストで isu1 に向けて実行する (~/isu-bench.sh に置く)
# 標準出力は競技者向けのログとエラーメッセージ、最終行に {"pass","score"}。標準エラー (staff log) は捨てる
cd /home/isucon
rm -f /tmp/result.json
ip=$(getent hosts "${TARGET:-isu1}" | awk "{print \$1}")   # bench の /etc/hosts に isu1・isu2 のプライベート IP を書いておく
./bench run --enable-ssl --target https://pipe.u.isucon.local --nameserver "$ip" --webapp "$ip" 2>/dev/null
python3 -c '
import json
try: r = json.load(open("/tmp/result.json"))
except Exception: r = {}
for m in r.get("messages") or []: print(m)
print(json.dumps({"pass": bool(r.get("pass")), "score": int(r.get("score") or 0)}))'
