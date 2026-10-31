#!/bin/sh
# リハーサル用: ポータルの負荷走行の代わり。bench 専用ホストで TARGET (既定 isu1) に向けて実行する (~/isu-bench.sh に置く。向き先の選択はポータルの操作に相当)
# 標準出力は競技者向けのログ、最終行に {"pass","score"}。標準エラー (staff log) は捨てる
# bench の /etc/hosts に isu1〜isu3 と isucondition-1〜3.t.isucon.dev のプライベート IP を書いておく。JIA の模擬サーバは bench 自身が 4999 で立てる
cd /home/isucon/bench
ip() { getent hosts "$1" | awk '{print $1}'; }
all=$(for h in isu1 isu2 isu3; do ip $h; done | paste -sd, -)
./bench -all-addresses "$all" -target "$(ip "${TARGET:-isu1}"):443" -tls -jia-service-url "http://$(hostname -I | awk '{print $1}'):4999" 2>/dev/null | tee /tmp/bench-out.txt
last=$(grep -E 'score: -?[0-9]+.* : (pass|fail)' /tmp/bench-out.txt | tail -n1)
score=$(echo "$last" | sed -nE 's/.*score: (-?[0-9]+).*/\1/p')
case $last in *": pass") pass=true ;; *) pass=false ;; esac
echo "{\"pass\":$pass,\"score\":${score:-0}}"
