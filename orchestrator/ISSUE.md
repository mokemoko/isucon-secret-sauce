# ISSUE

状態：`todo` / `doing` / `done` / `hold`

このファイルは課題管理だけに使う。本選の前日に空にし、当日は当日発生した課題（仕組みの不具合・運用の問題）だけを Coordinator が書き足す。
残すべき知見は空にする前に移す：orchestrator の運用知見 → `KNOWLEDGE.md`、ISUCON のチューニング・計測の知見 → `../knowledge/`（計測は `../knowledge/measurement.md`）

| # | 課題 | 状態 |
|---|---|---|
| 1 | [リハ#4] グローバル設定の sandbox が有効で、Coordinator が `orchestrator/state/` に書けず起動直後に止まった | done |
| 2 | restart-check.sh の PROBE_URLS が URL しか渡せず、認証必須の GET を probe にできない | done |
| 3 | worker_done 後の Dispatch は completed になり、`send --to dispatch:<id>` でリベースを頼めない（dispatch_inactive） | done |
| 4 | queue.sh rank がエンドポイントの時間占有だけで優先度を付け、時間占有は小さいがスコアへの効果が大きい変更（結果に応じた加点に効くもの）が常に最下位になる | done |
| 5 | [リハ#4] Coordinator が Phase 3 の開始を実装の締め切りとして扱い、spec で「小さく確実なものだけ」と絞った結果、在庫が尽きて Phase 3 を前倒しし、END の1時間20分前に終わった | done |
| 6 | [リハ#4] ベンチ枠の稼働率が50%（ベンチの間の空きの中央値81秒） | done |
| 7 | [リハ#4] 整合性の WARN（減点）が増えても verify は通り、LocalBench の改善も起動しなかった | done |
| 8 | [リハ#5] BENCH_WARN_RE の「エラー」がベンチの進捗行に含まれる固有名に当たり warnings_increased=yes を誤検知 | done |
| 9 | [リハ#5] アプリ内の DB（SQLite）のクエリが計測されず、MySQL のクエリ集計だけが summary に出た | todo |
| 10 | [リハ#5] Phase 3 が19分で終わり、END の26分前から何もしなかった | todo |
| 11 | [リハ#5] ベンチ枠の稼働率が31%（中断を除いて39%）、ベンチの間の空きの中央値127秒 | todo |
| 12 | [リハ#5] BENCH_WARN_RE が減点にならない行（打ち切り時の decode 失敗など）も数え、Coordinator が4回手で中身を確かめた | todo |

---

## 1. sandbox で state に書けない
- 現象：`~/.claude/settings.json` で sandbox が有効（`enabled: true`）。競技リポジトリで起動した Coordinator は、書き込みが競技リポジトリ内と一時ディレクトリに限られ、`$ORC/state/`（run_id・phase・end）への書き込みが Operation not permitted で失敗した。ssh（EC2・GitHub）もネットワーク制限で止まる見込み
- 影響：Phase 1 に入れない。ワーカーも同じ設定で起動するため全員が止まる
- 回避策：競技リポジトリの main に `.claude/settings.json`（`{"sandbox": {"enabled": false}}`）をコミットし、worktree にも効かせる。エージェントの sandbox を外す操作（設定のコミット、Coordinator の再起動）は auto モードの判定で止まるので、人間が行う
- 対応案：RUNBOOK の「開始直後」に、競技リポジトリへ sandbox 無効の設定を入れて Coordinator を起動する手順を足す
- 対応：RUNBOOK の手順5に、競技リポジトリへ sandbox 無効の設定を入れる人間の作業を足した。KNOWLEDGE.md に追記

## 2. PROBE_URLS に認証ヘッダを付けられない
- 現象：DB のデータを返す GET がすべて cookie 認証を要する問題だった。restart-check.sh は `curl -fsS '<url>'` だけを実行する
- 影響：PROBE_URLS を埋められず、再起動確認が動かない
- 回避策：setup タスクに PROBE_CURL_ARGS を追加させた（cookie は APP_HOST 上で DB から取り出して展開し、手元に持ち出さない）。DB を isu2 に移した後は、cookie の取得元を `mysql -h <isu2>` に書き換えた

## 3. 列で待つ Implementer にリベースを send できない
- 現象：coordinator.md は「release せずに残し、send --to dispatch:<id> でリベースを依頼」とするが、worker_done で Dispatch が completed になり、send が dispatch_inactive で拒否される（`send --to @claude` の一斉通知も同様に届かない）
- 影響：列のブランチの競合解消が指示どおりにできない
- 回避策：worker-show で terminal handle と worktree id を取り、新しいタスクを `worker-start --terminal <handle> --worktree id:<id>` で同じワーカーに投げる。元の task_id は列から外し、新しい task_id で積み直す（2件で実施）
- 対応：リベースは同じターミナルに新しいタスク（`worker-start --task <新> --terminal <handle>`）で渡す（coordinator.md の「リベースの頼み方」、implementer.md の「リベースタスク」）。`queue.sh requeue` で待ち時間を引き継ぐ。LocalBench の更新通知（`send --to @claude`）は廃止

## 4. 内部の定期処理の改善の優先度が 0 になる
- 現象：rank は targets のエンドポイントの時間占有 × 確信度で順位を付ける。アプリ内部の定期処理のエンドポイントは時間占有がほぼ 0 なので、その改善が常に最下位になる。実際にはその改善が最大級の伸び（2.4倍）だった
- 影響：効く変更が後回しになる。今回は列が短かったので実害は小さかった
- 回避策：人間に知らせたうえで順位どおりに流した。scoring.json の summary にある「結果に応じた加点」（処理の速さが利用者の増加につながるなど）を優先度に反映する仕組みが要る
- 対応：仮説に `degree_hint`（Analyst の見積もり）を足し、`queue.sh rank` は実測と大きい方を使う（表に h）

## 5. Phase 3 の開始を締め切りとして扱い、時間を残して終わった
- 現象：END 21:30（3時間）。Coordinator は 19:20 ごろから spec に「Phase 3 は 20:30 なので 20:15 までに worker_done」「小さく効果の大きいものだけ（N件以内、6〜10分以内にレポート）」と書いた。Analyst は最後の2回で、構造的な打ち手（遊休の isu3 の活用、書き込みの非同期化）を「時間内に不適」と見送り、最後は0件を返した。Coordinator は在庫切れを理由に期限付きゲートで Phase 3 の前倒しを求め、承認されて 20:05 に Phase 3 へ入り、20:09 に終えた
- 影響：END の1時間20分前に終了（3時間の44%を使わなかった）。Analyst の所要は中央値2分で、分析が浅くなった
- 対応案：Phase 3 の開始は「新規の Implementer の起動を止める時刻」で、それまでは通常どおり（大きい仮説も可）と coordinator.md に明記する。spec に分析・実装の制限時間を足さない。前倒しのゲートは「Analyst が構造的な打ち手まで検討して0件」のときだけ出す。短い競技時間では PHASE3_BEFORE を競技時間に比例させる（リハーサルの起動指示で上書きする）
- 対応：PHASE3_BEFORE を45分にし、Phase 3 の開始は「新しい Implementer の起動を止める時刻」と定義。spec に時間の制約を書かない、前倒しのゲートは時間以外の理由で0件のときだけ（coordinator.md）。Analyst は残り時間で仮説を落とさず、遊休ホストがあれば点検3を必ず出す（analyst.md）

## 6. ベンチ枠の稼働率が50%
- 現象：ベンチ30回（1回 平均93秒）で、最初から最後までの93分のうちベンチが動いていたのは46分。ベンチの間の空きは中央値81秒・最大6分。マージ待ちは中央値4分・最大16分あった
- 影響：#3（Phase 2 で76%）より下がった。測れたはずの変更が列で待った
- 対応案：Coordinator の記録で空きの内訳（採否の判定・insights の更新・Analyst の起動・列の処理）を確かめる。採否の判定とベンチの起動の間に挟む作業を、ベンチを走らせている間に回す
- 対応：ベンチの後の確認を `bin/after-bench.sh` にまとめた（判定・警告の増減・ボトルネックの移動・再起動確認の要否・列の順位と競合）。insights の書き換えと summary の読み込みは moved=yes のときだけ。列の競合の確認は `queue.sh rank` に移した。ベンチのバックグラウンド化はしない

## 7. 整合性の WARN を verify が見逃した
- 現象：キャッシュとトランザクション外しの後、ベンチの整合性の WARN（減点）が17件→103件に増えた。verify は通っていた。coordinator.md の LocalBench の起動条件は「整合性の fail」だけで、WARN では起動しなかった
- 影響：3回のベンチで減点を抱えたまま進み、原因の切り分けを Analyst が行った。修正後も WARN は 6〜7 件残った
- 対応案：LocalBench の起動条件に「ベンチの整合性の WARN・減点が増えた」を足す。verify が通ったのに本番で整合性のエラーが出た変更は、その不変条件を verify に足す
- 対応：digest.sh が bench.txt の警告・エラー（`BENCH_WARN_RE`）を `warnings.txt` に抜き出し、summary に件数を出す。after-bench.sh が前回より増えたら `warnings_increased=yes` を出し、Coordinator が LocalBench の改善を起動する

## 8 BENCH_WARN_RE の誤検知
- 現象: bench 134147-91a446d で、進捗行（データの名前に「エラー」を含む）が警告として数えられた
- 影響: LocalBench 改善の誤起動のおそれ
- 回避: env.sh の BENCH_WARN_RE から「エラー」を外した（実際のエラー行は error: / ERROR[n] 形式）

## 9. アプリ内の DB のクエリが見えない
- 現象：データの大半がテナントごとの SQLite（アプリのプロセス内）にあった。setup は MySQL の slow log と pt を入れ、受け入れ条件（主要な SELECT が queries.json に出ること）は「MySQL には出ない」として通した。SQLite 側の計測は入らず、アプリには SQLite のクエリトレースを出す環境変数が用意されていたが使われなかった
- 影響：最後まで queries.json は MySQL の INSERT だけで、pprof の `runtime.cgocall`（SQLite の呼び出し）が 53% と出るだけだった。どのクエリが重いかは Analyst がコードを読んで推した
- 対応案：recon.md の受け入れ条件を「アプリが使う全 DB」に広げる。アプリ内の DB（SQLite など）は、アプリやドライバのトレース機能・クエリログを使うアダプタ（`bin/digest/query-<tool>.sh`）を setup が足す。knowledge/measurement.md に選択肢を書く

## 10. Phase 3 の後に時間が余る
- 現象：15:15 に Phase 3 に入り、実行中の3本に 15:30 までの worker_done を指示した。列はすぐ空になり、15:25 に計測の無効化、15:28〜15:30 に final の再起動確認、15:34 に終了の承認が出た。END の16:00まで26分残った
- 影響：3時間の14%を使わなかった。8時間の本番でも、PHASE3_BEFORE=45 の大半が余る可能性がある
- 対応案（要相談）：(a) PHASE3_BEFORE を短くする（30分など）、(b) final の後も FREEZE_BEFORE までは、再起動確認をやり直す前提で小さな変更を採ってよいことにする、(c) Phase 3 の開始時に、残り時間に収まる実行中のタスクは待つ（期限を (PHASE3_BEFORE − FREEZE_BEFORE) / 2 で切らない）

## 11. ベンチ枠の稼働率
- 現象：ベンチ26回の稼働45分に対し、13:05〜15:30 の145分（31%）。ssh 不達の30分を除いても39%。ベンチの間の空きの中央値は127秒（#4 は81秒）。after-bench.sh を入れても縮まなかった
- 影響：13:41〜14:52 は人間が並列度を1にしていた分の割り引きがあるが、1回ごとの空きは仕組みの問題
- 対応案：Coordinator のセッション記録から、ベンチの終了から次のベンチの開始までの操作を分解して、何に時間を使ったかを調べる（判断・マージ・ワーカーの片付け・insights の更新など）

## 12. 減点にならない警告行の誤検知
- 現象：setup の調整後の BENCH_WARN_RE は `error` を含み、負荷走行の打ち切り時の decode 失敗（減点の集計 `Error 0` に入らない行）も数えた。warnings_increased=yes のたびに Coordinator が中身を見て「Error 0 なので問題なし」と判断した（4回）
- 影響：1回1分程度の確認と、本当の増加を見落とす下地
- 対応案：recon.md の BENCH_WARN_RE の調整で「ベースラインのベンチでほぼ0件になる」ことを確かめさせる。ベンチの出力に減点の集計（エラー件数）があれば、それを `warnings` の代わりに使えるよう env.sh に `BENCH_PENALTY_RE`（件数を取り出す正規表現）を足す
