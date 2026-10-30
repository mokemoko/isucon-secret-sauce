# ISSUE

状態：`todo` / `doing` / `done` / `hold`

このファイルは課題管理だけに使う。本選の前日に空にし、当日は当日発生した課題（仕組みの不具合・運用の問題）だけを Coordinator が書き足す。
残すべき知見は空にする前に移す：orchestrator の運用知見 → `KNOWLEDGE.md`、ISUCON のチューニング・計測の知見 → `../knowledge/`（計測は `../knowledge/measurement.md`）

| # | 課題 | 状態 |
|---|---|---|
| 22 | [リハ#7] measure-extra が実行中の bench.sh をその場で書き換え、ベースラインの1回が bench.jsonl に載らなかった | done |
| 23 | [リハ#7] queue.sh requeue 直後（リベースの worker_done 前）の項目が rank の .batch の先頭に出る | todo |
| 24 | [リハ#7] with-bench-lock.sh を STATE が相対パスの状態で使うと bench.lock が残る（Browser prod が報告） | done |
| 25 | [リハ#7] ベンチ1回176秒のうち約100秒が計測の待ち（pprof の seconds が負荷走行より長い、slow log の回収と pt の解析をロック中に行う） | todo |
| 26 | [リハ#7] Coordinator が `needs_human` のゲートに期限（既定は却下）を付け、expected_gain=high を含む3件が20分で自動却下された | done |
| 27 | [リハ#7] タスクのタイトルの `[要承認]` が二重になる（Analyst の title に既に付いている） | done |
| 28 | [リハ#8] deploy.sh の git fetch が GitHub ssh 認証で断続的に Permission denied (publickey) になり deploy failed、本番が半分だけ新しい版になる | doing |
| 29 | [リハ#8] bench.sh が deploy failed で終わっても after-bench.sh は bench.jsonl の最終行（前回のベンチ）を処理してしまう | done |
| 30 | [リハ#8] ダッシュボードのベンチ履歴で、retry のベンチにも「再起動」の印が付く（retry も SKIP_DEPLOY=1 で走り、restart_check=true で記録される） | todo |
| 31 | [リハ#8] after-bench.sh の「列を通らない変更」が、Coordinator のマージ（件名が一定しない）も検知していた | done |

---

## 22. bench.sh が台帳に追記せず終了（measure-extra の書き換え）
- 現象: `bench.sh origin/main baseline`（142911-40cd518）の出力が deploy の行で終わり、analysis/ と summary.md はできたが bench.jsonl に行が無い。プロセスは残っていない
- 影響: judge・ダッシュボードにベンチが出ない
- 原因: measure-extra が実行中の bench.sh をその場で編集した。bash はスクリプトを逐次読むため後半の処理がずれた
- 回避: bench.txt の最終行から同じ形式で手動追記した。measure-extra には $ORC/bin の差し替えを mv（別 inode）で行うよう依頼。recon.md の measure-extra 節に同じ注意を書くべき
- 対応: recon.md の measure-extra に「`$ORC/bin` のスクリプトは別ファイルに書いて mv で置き換える」を書いた

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
- 対応: coordinator.md に「期限付きゲートは Phase 3 の前倒しにだけ使い、ほかのゲートには期限を付けない」を書いた

## 27. `[要承認]` の二重付与
- 現象：Analyst が title に `[要承認] ` を付けて返し、Coordinator も付けた
- 影響：表示だけ（ダッシュボード・after-bench の照合は動いた）
- 対応: coordinator.md に「title が既に `[要承認]` で始まっていれば付け足さない」を書いた

## 28. deploy.sh の fetch が GitHub ssh 認証で断続的に失敗
- 現象: 23:20 ごろ、DB 分離（3a0dce6）の deploy で3台とも `git@github.com: Permission denied (publickey)`。同じ鍵の `ssh -T git@github.com` を連続で試すと、成功（deploy key として / エージェント転送の個人鍵として）と拒否が混ざる。deploy key は GitHub に登録済みで、サーバの id_ed25519 と一致している
- 影響: isu1 だけが新しい版に checkout され（mariadb を disable 済み）、isu2/isu3 は古い版のまま。DB の向き先がずれて、本番が壊れた状態になった
- 回避策: bench.sh を再実行して deploy をやり直す。deploy.sh で fetch をリトライするのが望ましい

## 29. deploy failed の後に after-bench.sh が前回のベンチを処理する
- 現象: bench.sh が deploy failed で終わり、bench.jsonl に行が足されないまま、`after-bench.sh $(tail -1 bench.jsonl)` が前回のベンチ（231619）の判定と列の表示をやり直した（verdicts.jsonl への重複追記は無かった）
- 回避策: bench.sh の終了コードを確かめてから after-bench.sh を呼ぶ
- 対応: coordinator.md に「bench.sh が 0 以外で終わったら after-bench.sh を呼ばない」を書き、after-bench.sh は判定済みのベンチに WARN 行を出す

## 30. retry のベンチに「再起動」の印
- 現象: `SKIP_DEPLOY=1 bench.sh HEAD "retry ..."` も `restart_check:true` で台帳に載り、ダッシュボードで再起動確認と区別できない
- 影響: 表示だけ（judge は同じ sha の組としてノイズ幅に使うので、扱いは正しい）
- 対応案: bench.sh に `KIND=retry|restart` を渡して台帳に残し、ダッシュボードは restart だけに印を付ける

## 31. 列を通らない変更の誤検知
- 現象: Coordinator のマージの件名は `Merge PR#3 ...`・`Merge local-env` のように一定せず、git の既定の `Merge remote-tracking branch` を前提にした判定ではすべて検知された
- 対応: 件名が `Merge `・`Revert ` で始まるものを列のものとみなし、直接 push（マージでも revert でもないコミット）と GitHub でのマージ（`Merge pull request #`）だけを出す。最初のベンチの後処理の前に直した

