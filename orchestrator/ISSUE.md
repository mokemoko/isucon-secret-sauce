# ISSUE

状態：`todo` / `doing` / `done` / `hold`

このファイルは課題管理だけに使う。本選の前日に空にし、当日は当日発生した課題（仕組みの不具合・運用の問題）だけを Coordinator が書き足す。
残すべき知見は空にする前に移す：orchestrator の運用知見 → `KNOWLEDGE.md`、ISUCON のチューニング・計測の知見 → `../knowledge/`（計測は `../knowledge/measurement.md`）

| # | 課題 | 状態 |
|---|---|---|
| 1 | [リハ#3] new-top-level worktree のブランチ名が `<git user>/<name>`（例 mokemoko/localbench-init）で、coordinator.md の `impl/<task_id>` と一致しない | todo |
| 2 | [リハ#3] クエリ集計（psdigest）がプリペアドステートメントのクエリを拾わない | todo |
| 3 | [リハ#3] 30分の一時停止が実際は約50分になり、A（END を30分延長）の前提（15:50 再開）が崩れて Phase 3 の開始を過ぎてから再開した | todo |
| 4 | [リハ#3] Implementer のブランチが古い base のままだと、終盤のマージで競合が多い（NG キャッシュ、予約軽量化、DB 分離） | todo |
| 5 | [リハ#3] DB_HOSTS がアプリの DB だけで、別用途の DB の負荷が見えない | todo |
| 6 | [リハ#3] Coordinator が列の順位・まとめ方・同時実行数の規則から外れた | todo |
| 7 | [リハ#3] 最終の再起動確認の後にマージして、確認をやり直した | todo |
| 8 | [リハ#3] Phase 2 開始のゲートで10分待った | todo |
| 9 | [リハ#3] 秘密を含む設定ファイルをリポジトリに入れられず、別経路の配置で0点 | todo |
| 10 | [リハ#3] appmap タスクが dispatched のまま終わらなかった | todo |
| 11 | [リハ#3] リハーサルの負荷走行の向き先が固定で、本番の「向き先の選択」を試せない | todo |

---

## 1. worker-start のブランチ名
- 現象：`--worktree new-top-level --name localbench-init` で作られたブランチが `mokemoko/localbench-init`
- 影響：coordinator.md の手順3 `git merge origin/impl/<task_id>` がそのままでは使えない
- 回避策：worktree ps / worker_done の要約で実際のブランチ名を確認してマージする

## 2. クエリ集計（psdigest）がプリペアドステートメントのクエリを拾わない
- 現象：Go の database/sql（interpolateParams なし）だと、引数つきのクエリはバイナリプロトコルで実行され、performance_schema の digest 集計に出ない可能性が高い。序盤のベンチでは上位30件のうち SELECT が4件だけで、COMMIT と初期化の INSERT が上位を占めた。interpolateParams を入れた後のベンチでは SELECT が18件に増えた
- 影響：序盤の一番重い SELECT が見えず、Analyst は endpoints・pprof・コードで代用した（insights に「queries は信頼できない」と書かれた）
- 対応案：setup の受け入れ条件に「アプリの主要な SELECT が queries.json に出ること」を入れ、出なければ slow log（`QUERY_DIGEST=pt`、long_query_time=0）に切り替える。`knowledge/measurement.md` に注意を書く。原因の確認（`events_statements_summary_by_digest` と `prepared_statements_instances` の挙動）は次のリハーサルで

- Coordinator の記録（リハ中）：query-psdigest.raw が30行のみで SELECT が落ちている。sum の単位混在か取得件数の制限を疑った。回避策は endpoints・pprof・コードで判断する

## 3. 一時停止と END
- 現象：人間の指示で一時停止。「30分延長」を選んで再開したのは 16:10 で、新しい Phase 3 の開始（16:00）を過ぎていた
- 影響：マージ待ちの列を流し切れず、DB 分離などを見送った
- 回避策：再開時に END を「停止時間の分だけ」延ばすか、その場で人間に聞く

## 4. 終盤の競合
- 現象：列で待つ間に main が進み、終盤のマージ3件が競合した
- 影響：リベースのためにワーカーを再起動する時間が無く、見送った
- 回避策：列で20分以上待ったものには、待っている間にリベースを依頼する

## 5. DB_HOSTS がアプリの DB だけで、別用途の DB の負荷が見えない
- 現象：アプリの DB を isu2 に分離した後、Coordinator が `DB_HOSTS` を isu2 だけにした。isu1 には別のミドルウェアのバックエンドの MySQL が残り、最終でも1コアの72%を使っていたが、クエリ集計の対象から外れた。resources には出ていたが、Analyst はボトルネックとして扱わなかった
- 影響：その DB を軽くする打ち手が終了まで未着手
- 対応案：`DB_HOSTS` は DB が動く全ホストにする（DB の役割を移しても外さない）。analyst.md の「毎回の点検」に「resources の上位プロセスのうち、endpoints・queries で説明できないものを調べる」を足す

## 6. Coordinator が列の順位・まとめ方・同時実行数の規則から外れた
- 現象：(1) `queue.sh rank` の先頭（`.batch`）が最大の打ち手だったのに、別の2件を独自にまとめて先に流した。うち1件は restart_risk（まとめの対象外）で、その結果0点になった。(2) Implementer を開始直後に8件同時に起動した（規定は最大3）
- 影響：最大の伸び（+34%）の採用が遅れ、その間に競合が生じてリベースが要った
- 対応案：列の順位を飛ばすのは人間の示唆があるときだけ、`.batch` を独自に組み替えない、を coordinator.md で強める。同時実行数は、ベンチ枠が律速であることを踏まえて上限を決め直す（人間の判断）

## 7. 最終の再起動確認の後にマージして、確認をやり直した
- 現象：Phase 3 で `restart-check.sh final` を実行した後に、DB 分離など2件をマージし、最終確認をもう一度行った
- 対応案：Phase 3 の手順で、最終の再起動確認は「最後のマージの後」と明記する

## 8. Phase 2 開始のゲートで10分待った
- 現象：ベースライン後の「Phase 2 を開始してよいか」の回答に10分かかり、稼働の約14%が空いた
- 対応案：期限付きゲート（例：5分で承認扱い）にする

## 9. 秘密を含む設定ファイルをリポジトリに入れられず、別経路の配置で0点
- 現象：setup はミドルウェアの設定ファイルを「認証情報を含む」として auto モードでリポジトリに入れられなかった。後の設定タスクがそのファイルを別の権限で配置し、初期化が 500 になって0点になった（1回、人間の判断で修正）
- 対応案：private リポジトリなので競技サーバの設定ファイルは入れてよい、と recon.md に明記するか、入れない場合は「deploy で配置しない」を setup の成果物に書く

## 10. appmap タスクが dispatched のまま終わらなかった
- 現象：app-map.md は書かれたが、タスクは終了まで dispatched のまま。worker_done が届かなかったか、Coordinator が処理しなかった
- 対応案：次のリハーサルで worker の画面と Coordinator の記録を確認する

## 11. リハーサルの負荷走行の向き先が固定で、本番の「向き先の選択」を試せない
- 現象：本番はポータルで負荷走行の向き先（名前解決の対象サーバ）を選べるが、リハーサルの注記で isu1 に固定した
- 対応案：ラッパー（`TARGET=isu2`）で選べるので、注記を「向き先は人間に頼めば変えられる（ポータルの操作に相当）」に変える。Coordinator が人間にゲートで頼む流れを試す
