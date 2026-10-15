# ISSUE

状態：`todo` / `doing` / `done` / `hold`

このファイルは課題管理だけに使う。本選の前日に空にし、当日は当日発生した課題（仕組みの不具合・運用の問題）だけを Coordinator が書き足す。
残すべき知見は空にする前に移す：orchestrator の運用知見 → `KNOWLEDGE.md`、ISUCON のチューニング・計測の知見 → `../knowledge/`（計測は `../knowledge/measurement.md`）

| # | 課題 | 状態 |
|---|---|---|
| 13 | [リハ#6] ワーカー（appmap）が Claude の API エラー（応答の途中切断）でターンを終え、worker_done を送らないまま dispatched で止まった | todo |
| 14 | [リハ#6] ダッシュボードの判断待ちの自由回答が、入力中に3秒ごとに消える | done |
| 15 | [リハ#6] クエリの計測の既定が performance_schema の digest 集計だが、プリペアドステートメントのクエリは digest に出ず、毎回 slow log に切り替えている | done |
| 16 | [リハ#6] queue.sh rank で20分待ちの `*` が付いた優先度 0.04 の項目が、0点の主因（優先度 1.14）より上の順位・次の batch になった | todo |
| 17 | [リハ#6] ベースラインから0点が続く間、0点解消タスクのベンチのたびに人間のゲートで止まる（原因が段階的に解けるときも毎回止まる） | todo |
| 18 | [リハ#6] PROBE_URLS のユーザがベンチで作られたもので、DB の移設後に再起動確認が止まった | todo |
| 19 | [リハ#6] Analyst が `needs_human` で出した「アプリの複数台化」に Coordinator がゲートを作らず、未着手のまま終わった（isu3・isu4 が最後まで遊休） | todo |
| 20 | [リハ#6] Phase 2 で Browser が起動されず（列が空の時間があった）、Phase 3 の本番の確認に初期状態の記録が無かった | todo |
| 21 | [リハ#6] アプリの env ファイル（DB の接続先・パスワード入り）を setup が auto モードの判定でリポジトリに入れられず、DB の移設に人間の手作業が要るとされた | todo |

---

## 13. API エラーでワーカーが worker_done を送らずに止まる
- 現象：appmap が起動から約1分後に `API Error: The response stopped arriving` でターンを終えた。Orca 上は dispatched・live のままで、activity だけが done。人間が UI で failed 表示に気づいて判明した（Coordinator の check には何も来ない）
- 影響：約20分、appmap が進まなかった。30分の点検（dispatched のまま30分）より前に気づく手段が無い
- 回避策：`orca terminal send --terminal <handle> --text "...再開..." --enter` で再開させた。点検で `worker-show` の `projection.stage.activity=done` かつ dispatched のものを拾うと早く気づける
- 対応案：メインループの「終わらないタスクの点検」を、30分を待たずタイムアウトのたびに行い、`worker-show` で `activity=done` かつ dispatched のワーカーに「worker_done を送るか作業を再開する」よう `orca terminal send` する

## 14. 判断待ちの自由回答が消える
- 現象：ダッシュボードは3秒ごとに判断待ちの一覧を描き直していた。フォーカスは戻すが入力欄の中身は戻さないため、自由回答を書いている途中で消える（日本語の変換中も切れる）
- 影響：ゲートに選択肢以外の回答を送れない
- 対応：ゲートの内容（id・質問・選択肢・送信済みの回答）が変わったときだけ描き直す。書きかけは gate id ごとに保持して描き直しでも戻す。変換中の Enter では送信しない。偽の orca でゲートを1件出し、入力から10秒後も残ることを確かめた

## 15. digest 集計にプリペアドステートメントのクエリが出ない
- 現象：リハーサル #3〜#6 のすべてで、setup が psdigest では主要な SELECT が見えないとして slow log + pt に切り替えた
- 事実確認（2026-10-15、手元の docker、MySQL 8.0.34 と 8.4.11、go-sql-driver/mysql v1.7.1）：`interpolateParams=false`（サーバ側のプリペアドステートメント）で SELECT・UPDATE を各50回流すと、`events_statements_summary_by_digest` には1件も出ず、`events_statements_summary_global_by_event_name` の `statement/com/Prepare`・`statement/com/Execute` の回数にだけ現れた。`db.Prepare` で明示的に準備した文（30回）も同じ。`interpolateParams=true`（テキストプロトコル）にすると digest に出た。`prepared_statements_instances` は Close 済みの文が消えるため、ベンチ後の集計には使えない
- 影響：アプリが既定のドライバ設定（多くの言語・ORM はサーバ側のプリペアドステートメント）なら、digest 集計では主要なクエリが見えない。setup が毎回切り替えの手間を払い、気づかなければ計測の死角になる
- 対応案：計測の既定を slow log（`long_query_time=0`）+ pt-query-digest にし、ベンチ中の slow log の書き込みがボトルネックになった（`resources.json` で mysqld の I/O・CPU が目立つ、slow log の量が大きい）ときと、アプリがテキストプロトコルで動くようになった（`interpolateParams` の導入後など）ときだけ digest に切り替える。recon.md の setup 手順・受け入れ条件、`env.example.sh` の `QUERY_DIGEST` の既定、`knowledge/measurement.md` の「既定」を入れ替える。Phase 3 の計測の無効化に slow log を止める手順は既にある。リハーサル中はプロンプトを変えないため、終了後に入れる
- 対応：既定を slow log + pt に入れ替えた（recon.md の setup、`env.example.sh` の `QUERY_DIGEST=pt`・`LOG_FILES`、`bin/bench.sh`・`bin/digest.sh` の既定値、`templates/mysqld.cnf`、`knowledge/measurement.md`・`middleware.md`）。digest への切り替えは、slow log の書き込みが重いときか、アプリがテキストプロトコルで実行するようになったときだけ

## 16. 待ち時間の優先が0点の解消を追い越す
- 現象：ベースラインが0点の間、20分以上待った（`*`）優先度 0.04 の項目が、0点の主因を直す優先度 1.14 の項目より上に並び、次の batch になった（Coordinator が気づいて止めた）
- 影響：0点の間に効果の小さい変更を測ることになる
- 対応案：queue.sh rank の AGE_MIN の繰り上げを、タイトルが `[0点解消]` の項目より上には上げない（または最新の pass ベンチが score 0 の間は繰り上げを止める）

## 17. 0点の解消のたびにゲートで止まる
- 現象：coordinator.md の「ベースラインから0点が続いている間は、0点の解消タスクのベンチが0点のままでも同じくゲートで判断を仰ぐ」に従い、1本目の0点解消（デッドロック）の後も0点のままでゲートになった。原因は2段（デッドロック → history の全走査）で、2本目の後に解消した
- 影響：0点の間は1本ごとに人間の回答を待つ。ベースラインからの立ち上げが遅れる
- 対応案：ベースラインから0点が続く間は、0点解消のベンチが0点のままでもゲートを出さず、減点の内訳（bench.txt のエラーの種類）が減っていれば次の0点解消を流す。エラーの種類が増えた・変わらないときだけゲート

## 18. PROBE_URLS のユーザがベンチで作られたものだった
- 現象：DB を isu2 に分離した後、restart-check.sh が「再起動前の時点で PROBE_URLS に失敗する URL がある」で止まった。/admin/user/1230 は、id_generator が 0 から採番されていた頃にベンチが isu1 の DB に作ったユーザで、isu2 には無い
- 回避策：初期データの最小 ID のユーザ（2626206）に差し替えた。probe は初期データにある ID を選ぶこと
- 対応案：recon.md の PROBE_URLS の選び方に「初期データ（初期化で戻るデータ）にある ID を使う。ベンチが作ったデータは初期化や DB の移設で消える」を足す

## 19. needs_human の仮説にゲートが作られない
- 現象：Analyst（174505）が「[restart] アプリを複数台に分散する（isu1 の nginx から isu1・isu3・isu4 の Go に振り分け）」を `needs_human=true` で出した。Coordinator はタスクを作ったが、ゲートを作らず、最後に failed で閉じた。DB の分離・縦分割にはゲートを作っていた
- 影響：isu3・isu4 は最後まで遊休。公式の講評では5台を App 1・DB 4 に使うのが良い配分だった
- 対応案：coordinator.md の Analyst の完了時の手順で、`needs_human` のものはタスク作成と同じ手順の中でゲートを作ることを明示し、タイムアウトのたびに「ゲートの無い needs_human のタスク」が無いかを点検する（task-list と gate-list の突き合わせ）

## 20. Phase 2 で Browser が起動されない
- 現象：22:55〜23:12 に列が空だったが、Browser（target=local）は起動されなかった。Phase 3 の Browser（target=prod）は `$STATE/browser/initial/` が無く、初期の API 応答の記録と比べた
- 影響：初期状態の画面の記録が無いので、挙動の違いを画面で比べられない
- 対応案：初期状態の記録を、在庫が減るのを待たずに Phase 2 の最初の空き（Implementer の枠の外）で取る（Browser の初回は記録だけ）。起動条件の点検をメインループのタイムアウトの点検に入れる

## 21. 認証情報を含む env ファイルをリポジトリに入れられない
- 現象：アプリの EnvironmentFile（DB の接続先・パスワード）を、setup が auto モードの判定（認証情報の持ち出し）でリポジトリに入れられず、「書き換えは人間の手作業」とした。DB の分離の Implementer は、systemd の drop-in（`EnvironmentFile=` を後から読ませて `ISUCON_DB_HOST` だけ上書き）をリポジトリに入れて回避した
- 影響：構成の変更のたびに人間の作業が要るように見え、ゲートが増える（#3 でも同じ種類の問題）
- 対応案：recon.md の setup に「認証情報を含むファイルを入れられないときは、原本はサーバに残し、変える値だけを上書きするファイル（systemd の drop-in、`conf.d/`、別の env ファイル）をリポジトリに入れて deploy する」を書く。knowledge にも同じパターンを足す
