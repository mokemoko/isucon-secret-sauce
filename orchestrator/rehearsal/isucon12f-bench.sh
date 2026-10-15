#!/bin/sh
# リハーサル用: ポータルの負荷走行の代わり。bench 専用ホストで TARGET (既定 isu1) に向けて実行する (~/isu-bench.sh に置く。向き先の選択はポータルの操作に相当)
# 標準出力 (結果の要約) だけを返し、最終行に {"pass","score"} を出す。標準エラー (ベンチマーカーの内部ログ) は捨てる
cd /home/isucon
ulimit -n 65536   # ssh 越しの既定 (1024) では、速くなるとベンチ側の接続が上限を超えて fail する
ip=$(getent hosts "${TARGET:-isu1}" | awk "{print \$1}")   # bench の /etc/hosts に isu1..isu5 のプライベート IP を書いておく
ISUXBENCH_TARGET=$ip ./bin/benchmarker --stage=prod --request-timeout=10s --initialize-request-timeout=60s 2>/dev/null | tee /tmp/isu-bench.out
pass=$(sed -n 's/.*\[PASSED\]: \([a-z]*\).*/\1/p' /tmp/isu-bench.out | tail -n1); score=$(sed -n 's/.*\[SCORE\] \([0-9-]*\).*/\1/p' /tmp/isu-bench.out | tail -n1)
echo "{\"pass\":${pass:-false},\"score\":${score:-0}}"
