#!/bin/sh
# リハーサル用: ポータルの負荷走行の代わり。bench 専用ホストで TARGET (既定 isu1) に向けて実行する (~/isu-bench.sh に置く。向き先の選択はポータルの操作に相当)
# 決済 API はベンチがこのホストの :12345 に立てる。アプリにはこのホストのプライベート IP を payment-url として渡す (/api/initialize 経由)
# 標準出力 (結果の要約) だけを返し、最終行に {"pass","score"} を出す。標準エラーのデバッグログ (ベンチマーカーの内部) は捨てる
cd /home/isucon
ip=$(getent hosts "${TARGET:-isu1}" | awk "{print \$1}")   # bench の /etc/hosts に isu1..isu3 のプライベート IP を書いておく
self=$(hostname -I | awk "{print \$1}")
./bench run --target https://xiv.isucon.net --addr "$ip:443" --payment-url "http://$self:12345" 2>/dev/null | tee /tmp/isu-bench.out
r=$(grep 'msg=結果 ' /tmp/isu-bench.out | tail -n1)
pass=$(echo "$r" | sed -n 's/.*pass=\([a-z]*\).*/\1/p'); score=$(echo "$r" | sed -n 's/.*スコア=\([0-9-]*\).*/\1/p')
echo "{\"pass\":${pass:-false},\"score\":${score:-0}}"
