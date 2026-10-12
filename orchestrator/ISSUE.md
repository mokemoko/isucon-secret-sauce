# ISSUE

リハーサル（2026-10-12、private-isu）後の課題一覧。上から順に検討・対応する。
状態：`todo` / `doing` / `done` / `hold`

このファイルは課題管理だけに使う。本選の前日に空にし、当日は当日発生した課題（仕組みの不具合・運用の問題）だけを Coordinator が書き足す。
残すべき知見は空にする前に移す：orchestrator の運用知見 → `KNOWLEDGE.md`、ISUCON のチューニング・計測の知見 → `../knowledge/`（計測は `../knowledge/measurement.md`）

| # | 課題 | 状態 |
|---|---|---|
| 1 | プロンプト内コマンド例の zsh 単語分割対策 | done |
| 2 | RUNBOOK にフォルダ信頼の手動承認を追記 | done |
| 3 | スコア 0 の間の採否基準 | done |
| 4 | ベンチマーカーのブラックボックス化（過去問実行時） | done |
| 5 | ダッシュボード：タスク表示を各10件＋全件切替、スコア履歴にタイムスタンプ | done |
| 6 | 計測出力（alp / pt-query-digest）の正規化・構造化 | done |
| 7 | ベンチ実行単位のサマリページ（構造化データの可視化＋元出力の切替） | done |
| 8 | ベンチ中のプロセス単位リソース推移 | done |
| 9 | 計測結果・採点ルール・競技中の知見を改善案の検討と採否に反映する経路 | done |
| 10 | ベンチ実行順の制御（ボトルネック度×確信度） | done |
| 13 | クエリ計測の既定を performance_schema digest 集計にする（slow log の負荷） | done |
| 11 | ローカル予測の精度（検証先を本番同等 AMI の EC2 に） | hold |
| 14 | setup の deploy key 登録が auto モードで止まる（リハ#2） | todo |
| 15 | ダッシュボード起動コマンドの `$END` が未定義（リハ#2） | todo |
| 16 | `bash -c` で包んだコマンドが Claude Code の承認待ちで止まる（リハ#2） | done |
| 14 | [リハ#2] setup の rsync・deploy key 生成が auto mode の権限判定で拒否される | todo |
| 15 | [リハ#2] 実行中 Dispatch のあるタスクに gate-create できない | todo |
| 16 | [リハ#2] 待機中ワーカーの入力欄に下書きがあると send が届かない | todo |
| 17 | [リハ#2] check --wait を重ねると2本目が「active actionable waiter」で失敗する | todo |
| 18 | [リハ#2] zsh の配列が1始まりで、Coordinator のタスク登録ループの表示名がずれた | todo |
| 19 | [リハ#2] PROBE_URLS が空だと restart-check.sh が再起動完了を待たずにベンチを走らせる | todo |

---

## 1. プロンプト内コマンド例の zsh 単語分割対策
- 現象：`$ids` のような未クオートの変数展開が zsh では単語分割されず、Coordinator が2回コマンドを壊した
- 対応案：common.md に「複数値の変数を引数に展開するときは `bash -c` で実行するか、zsh では `${=var}` を使う」と注意書きを足す。プロンプト内の例も合わせて見直す

## 2. RUNBOOK にフォルダ信頼の手動承認を追記
- 競技リポジトリで Claude Code のフォルダ信頼確認を、10:00 の開始時に人間が1回だけ承認する必要がある（auto モードでは代理承認できない）

## 3. スコア 0 の間の採否基準（done）
- 現象：ベスト pass スコアが 0 の間は `score >= 0 × (1 − ノイズ)` が常に真になり、どの変更も無条件に採用される
- 決定（人間）：0点の解消を最優先で実行することを大前提とし、それでも0点になった場合は人間の判断を挟む
- 対応：coordinator.md
  - ベースラインが0点なら、Phase 2 は「0点の解消」を最優先にし、解消するまで他の仮説はマージしない
  - ベンチが0点（fail または score 0）になったら、自動で採否を決めず、新しいマージとベンチを止めてゲートで人間に判断を仰ぐ（期限なし）

## 4. ベンチマーカーのブラックボックス化（過去問実行時）
- 本番ではベンチマーカーの実装は見られない。過去問ではサーバ上やリポジトリにソースがあるため、ワーカーが読むと本番と条件が変わる
- 対応案
  - env.sh に `BLACKBOX_PATHS`（例：`/home/isucon/private_isu/benchmarker`）を書く
  - Coordinator はワーカーの spec 冒頭に「以下のパスは読まない」を必ず入れる
  - 補強として、ワーカーの worktree の `.claude/settings.json` に `permissions.deny`（`Read(<path>/**)`、`Bash(ssh * <path>*)` など）を入れる。ssh 越しの読み取りまでは完全には防げない点を前提にする
  - ベンチ結果のメッセージ（bench.txt）は本番でも見られるので、読んでよい
- 対応（done）
  - common.md にブラックボックス節（BLACKBOX_PATHS 配下と過去問ベンチマーカーのソースを参照しない。記憶からの推測も根拠にしない）
  - coordinator.md：BLACKBOX_PATHS が空でなければ全 spec に参照禁止を明記し、ベンチマーカー内部に基づく仮説は破棄する
  - rehearsal/up.sh：起動時に benchmarker の bin/ と userdata/ 以外（ソース）を削除する。これがあれば ssh 越しでも読めない
  - `.claude/settings.json` の deny は見送り（ssh 越しの読み取りを防げず、ソースの削除で足りる）

## 5. ダッシュボードの表示改善
- 各ステータスのタスク表示を既定10件にし、「全件表示」で切り替える
- スコア履歴の各行にタイムスタンプ（JST の HH:MM:SS）を出す。`bench.jsonl` の `ts` を使う

## 6. 計測出力の正規化・構造化
- 現状
  - alp は表形式のテキスト（約3.8KB）。AI には冗長、人間にはダッシュボードで生テキストのリンクしかない
  - pt-query-digest は通常 4〜9KB だが、1回 1.2MB に膨れた（slow log 全量）
  - pprof はバイナリのまま。読むには `go tool pprof` が必要
- 方針：**「ツール → 共通スキーマの JSON」の変換層**を置き、AI と ダッシュボードはスキーマだけを読む。ツールは差し替え可能にする
  - `endpoints.json`：method, uri（正規化済み）, count, status 別件数, sum/avg/p99 秒, body 合計
  - `queries.json`：fingerprint, count, sum/avg/p99 秒, rows_examined/rows_sent 平均, サンプル SQL 1件
  - `profile.json`：上位 N 関数の flat/cum
  - AI 向けには上位 N 件・必要な列だけの短い要約テキスト（`summary.md`）も生成する
- 入力アダプタの候補（原案は既存ツール、代替を用意してロックインを避ける）
  - アクセスログ：alp（`--format tsv` 等の機械可読出力）→ 変換。代替：nginx の JSON/LTSV ログを自前で集計する小さな Go ツール（`script/accesslog-parser` を流用できるか検討）
  - スロークエリ：pt-query-digest `--output json` → 変換。代替：`performance_schema.events_statements_summary_by_digest` を SQL で取得（slow log 不要・軽量で、MySQL/MariaDB 共通）
  - プロファイル：`go tool pprof -top` → 変換。言語が Go 以外ならそのプロファイラに差し替え
- 検討点：変換をどこで行うか（bench.sh の後段で手元実行が第一候補）、URI 正規化ルールの持ち方（現状は alp.yml）
- 対応（done）
  - `bin/digest.sh`：bench.sh の後段で手元実行。`<host>/endpoints.json`・`queries.json`・`profile.json` と `summary.md` を作る。スキーマは digest.sh 冒頭に記載
  - アダプタは `bin/digest/<kind>-<tool>.sh`（引数は入力と元出力の保存先、stdout にスキーマ JSON）。env.sh の `ACCESS_DIGEST`/`QUERY_DIGEST`/`PROFILE_DIGEST` で選ぶ。今は `access-alp`・`query-pt`・`profile-pprof` の3本
  - alp は `--format json`、pt は `--output json --limit 30` を使い、サンプル SQL は300文字で切る。URI 正規化は従来どおり alp.yml
  - summary.md はリハーサル最大のベンチで 2.7KB（元出力は alp 3.8KB＋pt 1.2MB）。エンドポイント上位12、クエリ上位10（占有率つき）、CPU の flat 上位と main パッケージの cum 上位
  - pprof もホスト単位にした（env.sh の `PPROF_HOSTS` の各台から並列に取得し `<host>/cpu.pprof`・`<host>/profile.json`）。従来は APP_HOST の1台だけでベンチ直下に置いていた
  - 変換に失敗してもベンチ台帳への記録は止めない（理由は `digest.err` と summary.md 末尾）
  - Analyst と common.md は summary.md を最初に読むよう更新。リハーサルの全21ベンチを再変換済み
- 見送り（必要になったらアダプタを足す）
  - `performance_schema` の digest 集計によるクエリ取得（slow log 不要）。ベンチ前の TRUNCATE と DB 接続情報が要るため、DB が MySQL 以外のとき・slow log の負荷が問題になったときに作る
  - alp を使わないアクセスログ集計。alp は json/ltsv/regexp のログ形式に対応しているので当面不要
  - Go 以外の言語のプロファイラ

## 7. ベンチ実行単位のサマリページ
- 現状：ダッシュボードには最新ベンチの生ファイルへのリンクしかない
- 対応案：`/bench/<id>` ページを作る。スコア・pass/fail・メッセージ、エンドポイント表、クエリ表、プロファイル上位、リソース推移（#8）を表示し、各セクションで元の出力に切り替えられるようにする。前回ベンチとの差分（増減）も出す
- 6 の構造化データが前提
- 対応（done）
  - `dashboard/bench.html`（`/bench/?id=<id>`）と `/api/bench`（台帳行・前後のベンチ・ホスト別ファイル一覧。id は形式チェックでパストラバーサルを防ぐ）
  - 表示：結果・スコア・前回比・時刻、メモ・sha・task・ローカル予測、ベンチのメッセージ（末尾の `(GET /xxx)` を外して種類ごとに件数）、ホストごとのエンドポイント表・クエリ表・CPU プロファイル（flat 上位と main パッケージの cum 上位）
  - 各セクションは「表 / 元の出力」を切り替え。元の出力は押したときに読み、3000行を超える分は全文リンクにする（pt の元出力は 1.2MB ある）
  - 前回比は直前のベンチと endpoint（method+uri）・fingerprint で突き合わせ、▼（減）/▲（増）/new を出す
  - メイン画面：ベンチ履歴の id を詳細ページへのリンクにし、「最新解析」は summary.md と詳細リンクにした
  - 途中で見つけた不具合：バイナリを含むクエリで pt が値を置換できず、fingerprint が巨大になって表が崩れた。アダプタで制御文字を除き500文字に切り詰め、画面では3行に抑えた。`test/digest_test.sh` を追加
- 見送り：列ヘッダでの並べ替え、前回以外のベンチとの比較。要望が出たら足す

## 8. ベンチ中のプロセス単位リソース推移
- htop / netdata で見る情報（プロセスごとの CPU%、RSS、I/O、全体の CPU・メモリ・ネットワーク）をベンチ中に時系列で取る
- 対応案：ベンチ中に各ホストで1秒ごとにサンプリングし、終了後に回収して `resources.json` にする
  - 原案は `pidstat -u -r -d 1`（sysstat）。無い環境向けに `/proc` を読む数十行のシェルを代替として用意する
  - netdata は常駐が重く、外部送信の設定にも気を遣うので候補から外す
- 表示：#7 のページでプロセス別 CPU% の推移（上位数プロセス）とホスト全体の推移
- 対応（done）
  - `bin/sample-resources.sh`：bench.sh がベンチ中に全ホストで `ssh "timeout 1800 bash -s"` として流す。1秒ごとに /proc の生カウンタ（CPU、メモリ、lo 以外の NIC、物理ディスク、全プロセスの utime+stime と RSS）を出すだけで、追加インストール不要。サンプラー自身と子プロセスは除く
  - 停止：ベンチ後に `/tmp/isu-sampler-<id>.pid` を ssh で kill。接続断・timeout が後備え。`RESOURCE_SAMPLING=0` で無効化
  - `bin/digest/resources-proc.sh`：差分を計算して `<host>/resources.json`（ホスト user/sys/iowait/steal/mem %、rx/tx/rd/wr B/s、プロセスは同名合算で 1コア=100% の CPU と RSS、平均上位10）。summary.md にも要約を出す
  - 詳細ページに「リソース推移」：ホスト CPU とプロセス別 CPU（上位5）の折れ線（ホバーで縦線と値）、プロセス表、メモリ・ネットワーク・ディスクの平均
  - pidstat は使わなかった（sysstat が入っていない環境が多く、/proc で足りる）。netdata も常駐が重いので見送り
  - 検証：docker の Linux コンテナで実際に取得・停止を確認。`test/digest_test.sh` に変換の数値テスト（2コア・同名合算・終了/新規プロセス）を追加。実サーバ（ssh 越し）での確認は次のリハーサルで行う

## 9. 計測結果を改善案の検討・採否に反映する経路
- 現状（リハーサルで確認）
  - Analyst は起動時に該当ベンチの alp / pt / pprof を読んでおり、根拠に具体的な数値を書いていた（例：getIndex のクエリが DB 時間の72%）
  - ただし Analyst の起動は約20回のベンチ中3回だけ。それ以外のベンチ結果は誰も読んでいない
  - Coordinator はスコアしか見ていない。Implementer は計測結果を見ない
- 対応案：#6 の `summary.md` を各ベンチ後に生成し、Coordinator が毎回読んで「ボトルネックが移ったか」を判断する。移ったら Analyst を起動する。Implementer の spec にも該当エンドポイントやクエリの現状値を入れる
- 追加で見つかった不足（スコアに勾配がある採点ルールへの対応）
  - ボトルネックの順位が時間の占有率だけで決まり、採点の重みが入っていない
  - 採点ルールが文章だけで、機械で読めない（#10 で使えない）
  - 競技中に分かったことを共有の文書に書き戻す仕組みが無い
  - Implementer に「採点上なぜ重要か」が伝わらない
- 対応（done）
  - 採点モデル `$STATE/docs/scoring.json`：manual タスクが作る（summary / endpoints[{method, uri, weight, note}] / penalties / consistency）。uri は alp の matching_groups と同じ書き方。推測で重みを付けない
  - digest.sh が endpoints.json に `weight` を付け、summary.md に weight 列と「加点ありの時間比率」を出す。詳細ページにも重みの列と比率。`test/digest_test.sh` に照合のテスト
  - 競技中の知見 `$STATE/docs/insights.md`：Coordinator だけが書く（採点の知見・ベンチマーカーの挙動・現在のボトルネック・却下した仮説・人間の方針）。全ワーカーが docs/ を読むので自動的に配られる。メイン画面に表示
  - Coordinator は採否の判定のたびに summary.md を読み、ボトルネックが移ったら Analyst を起動する
  - Analyst の出力に `scoring_rationale`。Coordinator は spec に evidence と合わせて「根拠」節として渡し、Implementer は根拠と矛盾する変更をしない
  - LocalBench のスコアの重みも scoring.json から取る

## 10. ベンチ実行順の制御
- 現状：Implementer が終わった順にマージしてベンチを回すので、ボトルネックではない改善が先に入ると効果が見えにくい（スコアが動かず、ノイズで revert されることもある）
- 対応案：完了したブランチをすぐマージせず「マージ待ち」に置き、ベンチの枠が空いたときに優先度の最も高いものを1つ選ぶ
  - 優先度 = 現在のボトルネック度（#6 の最新データで、そのタスクの area が占める時間の割合）× 確信度（Analyst の expected_gain と、Implementer のローカル予測）
  - 待たせすぎ防止：一定時間（例：20分）待ったものは優先度を上げる
  - 終盤（Phase 3 前）はマージ待ちを全部流す
- #6・#9 が前提
- 対応（done）
  - `bin/queue.sh`（add / rank / pop）。Coordinator は Implementer の完了を `$STATE/merge-queue.json` に積み、ベンチの枠が空いたら rank の先頭を処理する。列に1つなら待たない。人間の示唆での割り込みは可
  - 優先度 = ボトルネック度 × 確信度。ボトルネック度は最新の pass ベンチで targets が占める時間の割合（エンドポイントは採点の重みで補正：重みあり ×1・0 ×0.3・未記載 ×0.6。クエリもエンドポイントの合計時間を分母にして比べられるようにする）。確信度は expected_gain とローカル予測の平均。20分以上待ったものは先頭
  - Analyst の出力に `targets`（method+uri、クエリの部分文字列）
  - Phase 3 では列を優先度順に流し切り、回しきれない分は優先度の低いものから捨てる
  - ダッシュボードのメイン画面に「マージ待ち」（優先度・内訳・待ち時間）
  - `test/queue_test.sh`（順位、待ちすぎ、pop・置き換え、ベンチ無し）
- 見送り：同時に複数をまとめてベンチする（スループットは上がるが、効果の切り分けができなくなるので採らない）

## 11. ローカル予測の精度（hold）
- 予測と実績の差が −247pt〜+27pt。ローカル MySQL を CPU 0.3 に絞る調整では限界がある
- 案：検証先を本番と同じ AMI の EC2 にする（ワーカーは Mac のまま、起動は人間がスクリプトで）。AMI 複製の可否を Discord で確認する必要がある

## 13. クエリ計測の既定を performance_schema digest 集計にする（done）
- 背景：slow log（`long_query_time=0`）は全クエリをファイルに書くため負荷が大きく、DB 向けの改善を過大に見せる。比較の詳細は `../knowledge/measurement.md`
- 対応
  - `bin/digest/query-psdigest.collect.sh`（ベンチ前に TRUNCATE、ベンチ後に上位 30 種を TSV で取得）と `query-psdigest.sh`（queries スキーマへ変換。`no_index_used`・`tmp_disk_tables` を追加）
  - bench.sh：選んだクエリアダプタに `.collect.sh` があれば `DB_HOSTS` で pre/post を呼ぶ。env を `set -a` で読み込みアダプタに渡す
  - 既定を `QUERY_DIGEST=psdigest` に。slow log は MariaDB か深掘りのときだけ（`QUERY_DIGEST=pt`）
  - recon の setup は slow log を有効にせず digest を確認する。構成が違えば `knowledge/measurement.md` を読んで選ぶ
  - 詳細ページ・summary.md にインデックス未使用の回数を出す
  - 検証：docker の mysql:8.0 で取得・変換を確認。`test/digest_test.sh` に変換（エスケープ・ピコ秒・NULL）、`test/bench_test.sh` に pre→ベンチ→post の順序のテストを追加
- 残り：PostgreSQL のアダプタは当日 PG だったら setup で作る（作り方は `knowledge/measurement.md`）

## 14. [リハ#2] setup の rsync・deploy key 生成が auto mode の権限判定で拒否される
- 現象：setup ワーカーの isu1→ローカル repo への rsync と、isu1 上の ssh-keygen＋gh repo deploy-key add が auto mode の分類器に拒否され、escalation で停止
- 影響：Phase 1 のクリティカルパス（setup→ベースライン）が人間の対応待ちで止まる
- その場の回避策：判断用タスクにゲートを出し、人間に許可または手動実施を依頼。事前に settings の allow に入れておくか、RUNBOOK の手順に deploy key の用意を入れるのが本筋

## 15. [リハ#2] 実行中 Dispatch のあるタスクに gate-create できない
- 現象：`gate-create --task <setup>` が `task_not_startable`（Dispatch が active）で拒否された
- 影響：coordinator.md の「question/escalation は gate-create で人間に回す」がそのままでは実行できない
- その場の回避策：判断用のタスク（ワーカーを起動しない）を task-create してそこに gate を付ける。coordinator.md に明記すべき

## 14. setup の deploy key 登録が auto モードで止まる（リハ#2）
- 現象：setup が `gh repo deploy-key add ... --allow-write` を実行しようとして、auto モードの分類器に「Permission Grant」として止められ、人間の承認待ちになった
- 対応案：RUNBOOK の開始直後の手順で人間が登録する（サーバで `ssh-keygen` → `gh repo deploy-key add`）か、このコマンドだけを許可ルールに入れる

## 15. ダッシュボード起動コマンドの `$END` が未定義（リハ#2）
- 現象：coordinator.md が `go run . -run <run_id> -end $END` を人間に伝えるが、`$END` をどこにも定義していない。人間はコマンドを受け取れず、ダッシュボードが起動しなかった
- 対応案：競技の終了時刻を人間が `state/docs/` に書く（RUNBOOK の手順に追加）か、ダッシュボードの `-end` を省略可能にする

## 16. [リハ#2] 待機中ワーカーの入力欄に下書きがあると send が届かない
- 現象：escalation 後に待機していた setup ワーカーへ再開の send を送ったが、入力欄に人間の未送信の下書きが残っていて、ワーカーが通知を取り込まなかった
- 影響：ゲートを解決しても setup が再開せず、Phase 1 のクリティカルパスが止まった
- その場の回避策：人間に下書きを送信してもらう。Coordinator は send 後に worker-read でワーカーが取り込んだかを確認する

## 17. [リハ#2] check --wait を重ねると2本目が「active actionable waiter」で失敗する
- 現象：バックグラウンドの check --wait が残ったまま別の check --wait を出すと、`already has an active actionable waiter` で失敗する。jq に通していると原因が見えない
- 影響：Coordinator が待機を見失い、メッセージを取りこぼしたように見える
- その場の回避策：check --wait は常に1本だけにする（pgrep で残りを確認）。Run 単位で待機は1本という前提を coordinator.md に書くべき

## 18. [リハ#2] zsh の配列が1始まりで、Coordinator のタスク登録ループの表示名がずれた
- 現象：仮説を task-create するループで `names[i]`（0始まりのつもり）を使い、display-name が1件ずつずれた
- 影響：ダッシュボードの表示名が実際の仮説と食い違う（task_title は正しい）
- その場の回避策：対応表を作り直した。common.md の zsh の注意に「配列は1始まり」を足すか、ループは bash -c で書く

## 19. [リハ#2] PROBE_URLS が空だと restart-check.sh が再起動完了を待たずにベンチを走らせる
- 現象：setup が PROBE_URLS を埋めておらず、snapshot が再起動前後とも空文字の shasum で即一致。reboot から15秒でベンチを開始し、ssh 切断で `bench command failed`（201510-2293ef9）
- 影響：アプリは正常なのに restart-check が fail になり、手順どおりなら不要な revert をするところだった
- その場の回避策：isu1 のサービスが active になるのを待ってから `SKIP_DEPLOY=1 bin/bench.sh HEAD` を手動で再実行。restart-check.sh は PROBE_URLS が空なら失敗させるか、ssh の疎通とサービスの active を待つべき。setup の受け入れ条件に PROBE_URLS を入れる

## 16. `bash -c` で包んだコマンドが Claude Code の承認待ちで止まる（リハ#2）
- 現象：Coordinator が仮説8件のタスク登録を `bash -c '...'` で一括実行し、「This shell -c script ... could not be checked」で人間の承認待ちになった。Orca のゲートではないのでダッシュボードには出ない。無人なら約1分半で自動拒否
- 原因：課題1の対策で common.md が zsh の単語分割の回避策として `bash -c` を勧めていた
- 対応：common.md から `bash -c` の推奨を外し、`bash -c`・`sh -c`・`eval` で包まないと明記した。定型の一括処理（仮説 JSON → タスク登録）をスクリプト化するかは、リハーサル後に検討する
