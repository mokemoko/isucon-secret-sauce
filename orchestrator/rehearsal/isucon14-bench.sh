#!/bin/sh
# リハーサル用: ポータルの負荷走行の代わり。標準出力 (結果の要約) だけを返し、最終行に {"pass","score"} を出す
# 標準エラーのデバッグログ (ベンチマーカーの内部) は捨てる
cd /home/isucon
./bench run --target https://xiv.isucon.net --addr 127.0.0.1:443 2>/dev/null | tee /tmp/isu-bench.out
r=$(grep 'msg=結果 ' /tmp/isu-bench.out | tail -n1)
pass=$(echo "$r" | sed -n 's/.*pass=\([a-z]*\).*/\1/p'); score=$(echo "$r" | sed -n 's/.*スコア=\([0-9-]*\).*/\1/p')
echo "{\"pass\":${pass:-false},\"score\":${score:-0}}"
