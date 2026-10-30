# ISSUE

状態：`todo` / `doing` / `done` / `hold`

このファイルは課題管理だけに使う。本選の前日に空にし、当日は当日発生した課題（仕組みの不具合・運用の問題）だけを Coordinator が書き足す。
残すべき知見は空にする前に移す：orchestrator の運用知見 → `KNOWLEDGE.md`、ISUCON のチューニング・計測の知見 → `../knowledge/`（計測は `../knowledge/measurement.md`）

| # | 課題 | 状態 |
|---|---|---|
| 22 | [リハ#7] measure-extra が実行中の bench.sh をその場で書き換え、ベースラインの1回が bench.jsonl に載らなかった | todo |
| 23 | [リハ#7] queue.sh requeue 直後（リベースの worker_done 前）の項目が rank の .batch の先頭に出る | todo |
| 24 | [リハ#7] with-bench-lock.sh を STATE が相対パスの状態で使うと bench.lock が残る（Browser prod が報告） | done |
| 25 | [リハ#7] ベンチ1回176秒のうち約100秒が計測の待ち（pprof の seconds が負荷走行より長い、slow log の回収と pt の解析をロック中に行う） | todo |
| 26 | [リハ#7] Coordinator が `needs_human` のゲートに期限（既定は却下）を付け、expected_gain=high を含む3件が20分で自動却下された | todo |
| 27 | [リハ#7] タスクのタイトルの `[要承認]` が二重になる（Analyst の title に既に付いている） | todo |

---

## 22. bench.sh が台帳に追記せず終了（measure-extra の書き換え）
- 現象: `bench.sh origin/main baseline`（142911-40cd518）の出力が deploy の行で終わり、analysis/ と summary.md はできたが bench.jsonl に行が無い。プロセスは残っていない
- 影響: judge・ダッシュボードにベンチが出ない
- 原因: measure-extra が実行中の bench.sh をその場で編集した。bash はスクリプトを逐次読むため後半の処理がずれた
- 回避: bench.txt の最終行から同じ形式で手動追記した。measure-extra には $ORC/bin の差し替えを mv（別 inode）で行うよう依頼。recon.md の measure-extra 節に同じ注意を書くべき

## 23. リベース中の項目が .batch に出る
- 現象: `queue.sh requeue` で付け替えた項目が、リベースタスクの worker_done 前から rank の先頭・.batch に出る（競合フラグも古いブランチで判定）
- 影響: .batch に従うとワーカーの worker_done 前のブランチをマージしてしまう（禁止事項）
- 回避: リベース中の項目は飛ばし、次の項目を単独で流した。requeue に「worker_done 待ち」の状態を持たせ、rank で除外すべき

## 24. with-bench-lock.sh の相対パス
- 現象: Browser（target=prod）が STATE を相対パスで with-bench-lock.sh を使い、bench.lock が残った（本人が手で解除）
- 影響: 次の bench.sh が mkdir ロックで永久待ちになる
- 回避: STATE を絶対パスで渡す。スクリプト側で STATE を絶対パスに正規化すべき
- 対応: ロックを本番サーバ上（`bin/lock.sh`）に移し、STATE に依存しなくなった

## 25. ベンチ枠の約6割が計測の待ち
- 現象：ベンチ1回の平均176秒のうち、負荷走行は約70秒。pprof の `seconds=110`（setup が設定）を待つのに約40秒、slow log（1回で数百 MB）の回収と pt-query-digest に50〜94秒かかり、その間ずっとベンチのロックを持つ。計測を止めた後は74秒
- 影響：41回のベンチで約70分が計測の待ち。同じ時間で倍近いベンチを回せた
- 補足：measurement.md の「`interpolateParams=true` を入れたら digest に切り替える」は、14:46 に入った後も使われなかった

## 26. needs_human のゲートが期限切れで自動却下
- 現象：Coordinator が `needs_human` の仮説3件のゲートに「17:00 までに回答が無ければ却下」の期限を付け、20分で自動却下した。期限付きゲートは Phase 3 の前倒しにだけ使う規定だが、`needs_human` のゲートに期限を付けてはいけないとは書いていない
- 影響：expected_gain=high の「HTTPS の終端を isu3 に分ける」（最後の律速は isu1 の nginx）と、水責めへの対処が未着手で終わった

## 27. `[要承認]` の二重付与
- 現象：Analyst が title に `[要承認] ` を付けて返し、Coordinator も付けた
- 影響：表示だけ（ダッシュボード・after-bench の照合は動いた）
