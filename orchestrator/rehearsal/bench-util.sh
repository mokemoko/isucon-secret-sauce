#!/usr/bin/env bash
# usage: rehearsal/bench-util.sh [state ディレクトリ (既定 state)]
# リハーサルの評価用: ベンチ枠の稼働率を「列に待ちがあった時間」と「列が空だった時間」に分けて出す
#   ベンチの開始 = bench.jsonl の id の先頭6桁 (手元の時刻 HHMMSS)、終了 = ts (UTC)
#   列の長さ = queue.log (queue.sh が add・pop・requeue のたびに残す)。ベンチの直前の pop で長さが0になっても、そのベンチの間は稼働として数える
# 出力: 稼働・列に待ちがあったのに空いた時間 (= 判断・作業の空き)・列が空で空いた時間 (= 変更の供給不足)、と空きの中央値
set -euo pipefail
st=${1:-state}
python3 - "$st" <<'PY'
import sys, json, datetime as d, statistics, os
st = sys.argv[1]
rows = [json.loads(l) for l in open(f"{st}/bench.jsonl") if l.strip()]
if not rows: sys.exit("bench.jsonl が空")
def end(r): return d.datetime.strptime(r["ts"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=d.timezone.utc).timestamp()
def start(r):
    e = d.datetime.fromtimestamp(end(r))           # 手元の時刻で、終了日の HHMMSS を開始とみなす
    s = e.replace(hour=int(r["id"][0:2]), minute=int(r["id"][2:4]), second=int(r["id"][4:6]))
    if s > e: s -= d.timedelta(days=1)
    return s.timestamp()
benches = [(start(r), end(r)) for r in rows]
qlog = []
if os.path.exists(f"{st}/queue.log"):
    qlog = [tuple(l.rstrip("\n").split("\t")) for l in open(f"{st}/queue.log") if l.strip()]
    qlog = [(int(t), int(n)) for t, _, n in qlog]
def qlen(t):
    n = 0
    for tt, nn in qlog:
        if tt <= t: n = nn
        else: break
    return n
busy = sum(e - s for s, e in benches)
with_q = empty = 0; gaps_q = []
for (s0, e0), (s1, e1) in zip(benches, benches[1:]):
    t = e0; g_q = 0
    while t < s1:                                  # 10秒刻みで列の長さを見る
        step = min(10, s1 - t)
        if qlen(t) > 0: with_q += step; g_q += step
        else: empty += step
        t += step
    if g_q: gaps_q.append(g_q)
span = benches[-1][1] - benches[0][0]
m = lambda x: round(x / 60, 1)
print(f"区間 {m(span)}分 (ベンチ {len(benches)}回、平均 {round(busy/len(benches))}秒)")
print(f"稼働 {m(busy)}分 ({round(busy/span*100)}%)")
if qlog:
    print(f"列に待ちがあったのに空いた {m(with_q)}分 (中央値 {round(statistics.median(gaps_q)) if gaps_q else 0}秒/回) → 列に待ちがあった時間での稼働率 {round(busy/(busy+with_q)*100)}%")
    print(f"列が空で空いた {m(empty)}分 (変更の供給不足・0点の対応・中断など)")
else:
    print("queue.log が無いので、空きの内訳は出せない")
PY
