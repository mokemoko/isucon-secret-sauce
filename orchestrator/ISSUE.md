# ISSUE

状態：`todo` / `doing` / `done` / `hold`

このファイルは課題管理だけに使う。本選の前日に空にし、当日は当日発生した課題（仕組みの不具合・運用の問題）だけを Coordinator が書き足す。
残すべき知見は空にする前に移す：orchestrator の運用知見 → `KNOWLEDGE.md`、ISUCON のチューニング・計測の知見 → `../knowledge/`（計測は `../knowledge/measurement.md`）

| # | 課題 | 状態 |
|---|---|---|
| 13 | [リハ#6] ワーカー（appmap）が Claude の API エラー（応答の途中切断）でターンを終え、worker_done を送らないまま dispatched で止まった | doing |
| 14 | [リハ#6] ダッシュボードの判断待ちの自由回答が、入力中に3秒ごとに消える | done |
| 15 | [リハ#6] クエリの計測の既定が performance_schema の digest 集計だが、プリペアドステートメントのクエリは digest に出ず、毎回 slow log に切り替えている | todo |

---

## 13. API エラーでワーカーが worker_done を送らずに止まる
- 現象：appmap が起動から約1分後に `API Error: The response stopped arriving` でターンを終えた。Orca 上は dispatched・live のままで、activity だけが done。人間が UI で failed 表示に気づいて判明した（Coordinator の check には何も来ない）
- 影響：約20分、appmap が進まなかった。30分の点検（dispatched のまま30分）より前に気づく手段が無い
- 回避策：`orca terminal send --terminal <handle> --text "...再開..." --enter` で再開させた。点検で `worker-show` の `projection.stage.activity=done` かつ dispatched のものを拾うと早く気づける

## 14. 判断待ちの自由回答が消える
- 現象：ダッシュボードは3秒ごとに判断待ちの一覧を描き直していた。フォーカスは戻すが入力欄の中身は戻さないため、自由回答を書いている途中で消える（日本語の変換中も切れる）
- 影響：ゲートに選択肢以外の回答を送れない
- 対応：ゲートの内容（id・質問・選択肢・送信済みの回答）が変わったときだけ描き直す。書きかけは gate id ごとに保持して描き直しでも戻す。変換中の Enter では送信しない。偽の orca でゲートを1件出し、入力から10秒後も残ることを確かめた

## 15. digest 集計にプリペアドステートメントのクエリが出ない
- 現象：リハーサル #3〜#6 のすべてで、setup が psdigest では主要な SELECT が見えないとして slow log + pt に切り替えた
- 事実確認（2026-10-15、手元の docker、MySQL 8.0.34 と 8.4.11、go-sql-driver/mysql v1.7.1）：`interpolateParams=false`（サーバ側のプリペアドステートメント）で SELECT・UPDATE を各50回流すと、`events_statements_summary_by_digest` には1件も出ず、`events_statements_summary_global_by_event_name` の `statement/com/Prepare`・`statement/com/Execute` の回数にだけ現れた。`db.Prepare` で明示的に準備した文（30回）も同じ。`interpolateParams=true`（テキストプロトコル）にすると digest に出た。`prepared_statements_instances` は Close 済みの文が消えるため、ベンチ後の集計には使えない
- 影響：アプリが既定のドライバ設定（多くの言語・ORM はサーバ側のプリペアドステートメント）なら、digest 集計では主要なクエリが見えない。setup が毎回切り替えの手間を払い、気づかなければ計測の死角になる
- 対応案：計測の既定を slow log（`long_query_time=0`）+ pt-query-digest にし、ベンチ中の slow log の書き込みがボトルネックになった（`resources.json` で mysqld の I/O・CPU が目立つ、slow log の量が大きい）ときと、アプリがテキストプロトコルで動くようになった（`interpolateParams` の導入後など）ときだけ digest に切り替える。recon.md の setup 手順・受け入れ条件、`env.example.sh` の `QUERY_DIGEST` の既定、`knowledge/measurement.md` の「既定」を入れ替える。Phase 3 の計測の無効化に slow log を止める手順は既にある。リハーサル中はプロンプトを変えないため、終了後に入れる
