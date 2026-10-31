# 計測の知見（構成・環境ごとの選択肢）

ISUCON で何をどう計測するか。本番の構成が想定と違ったときに、ここから選ぶ。
orchestrator の実装（`orchestrator/bin/digest/` のアダプタ）との対応も書く。

## 前提：計測は負荷になる
採否は「同じ計測条件での変更前後」で比べるので大きくは狂わないが、計測の負荷が DB 側に偏ると、DB 向けの改善が過大に、アプリ向けの改善が過小に見える。
本番の採点は計測なしで行われるので、最終盤に必ず止める（orchestrator では Phase 3 の「計測の無効化」）。

| 計測 | 負荷 | 備考 |
|---|---|---|
| MySQL slow log（`long_query_time=0`） | **大**。全クエリをファイルに書き、書き込みはロックで直列化される | 過去の実測で1分のベンチ = 66MB |
| pprof（ベンチ中 60 秒の CPU プロファイル） | 小〜中（数%程度とされる） | 100Hz の SIGPROF でスタックを取る |
| nginx アクセスログ | 小 | `access_log <path> <format> buffer=64k flush=1s;` で write を減らす |
| /proc サンプラー（`orchestrator/bin/sample-resources.sh`） | ごく小 | 過去の実測：300 プロセスの環境で 30 秒に CPU 0.53 秒（1コアの約1.8%）、送信 約5.5KB/s |
| performance_schema digest 集計 | ほぼ無し | MySQL 8.0 は既定で有効なので、負荷はすでに払っている |
| ログ回収・alp / pt / pprof の解析 | 無し | ベンチ後に手元で実行 |

## クエリの計測

### MySQL：slow log + pt-query-digest（既定）
- アダプタ：`QUERY_DIGEST=pt`。slow log（`long_query_time=0`）を有効にし、パスを `LOG_FILES` に足す
- 既定にする理由：アプリの多くはサーバ側のプリペアドステートメントでクエリを実行し、それは digest 集計に出ない（下の psdigest の制約）。slow log は COM_STMT_EXECUTE も実 SQL で記録する
- 使う場面：常用。加えて、遅い実 SQL をパラメータ付きで全件見て EXPLAIN したい、ベンチ中のどの時点で遅くなったかを追いたいとき
- 負荷：全クエリを書くので大きい（上の表）。digest に切り替えるのは、(1) slow log の書き込みが目立つ（`resources.json` で mysqld の iowait・CPU が高い、1回の slow log が数百 MB）とき、(2) アプリがテキストプロトコルで実行するようになった（Go なら DSN に `interpolateParams=true` を入れた後など）とき。切り替えたら主要な SELECT が digest に出ることを確かめる
- pt の注意
  - テキスト出力はバイナリを含む INSERT の例をそのまま載せて巨大になる（過去の実測で 1.2MB）。`--output json` を使う
  - バイナリを含むクエリは値を `?` に置換できず fingerprint にバイナリが残ることがある。制御文字を除いて切り詰める
  - 30 秒ごとの進捗表示が stderr に出る。`--progress time,86400` で止める
  - 初期化（`/initialize`）の大量の INSERT・LOAD DATA も記録される。初期化の時間を短くしたいときは、初期化中だけ slow log を止める（`SET GLOBAL slow_query_log=0` → 戻す）

### MySQL 8.0：performance_schema の digest 集計（軽い代替）
- アダプタ：`QUERY_DIGEST=psdigest`（`query-psdigest.collect.sh` がベンチ前に `TRUNCATE`、ベンチ後に上位 30 種を取得）
- 確認：`SELECT ENABLED FROM performance_schema.setup_consumers WHERE NAME='statements_digest';` が YES
- 取れる：回数、合計・平均・最大・p95（`QUANTILE_95`）、ロック時間、走査行数、返却行数、インデックス未使用の回数（`SUM_NO_INDEX_USED` + `SUM_NO_GOOD_INDEX_USED`）、ディスク一時テーブル、最も遅かった実 SQL 1件（`QUERY_SAMPLE_TEXT`）
- 制約
  - 正規化 SQL・サンプル SQL は既定 1024 バイトで切られる（`max_digest_length`、`performance_schema_max_sql_text_length`。変更は再起動が要る）
  - 累積値のみで時系列は無い。サンプルは `performance_schema_max_digest_sample_age`（既定60秒）より古いと次の実行で置き換わる
  - `TRUNCATE` には DROP 権限が要る。サーバ上の `sudo mysql`（root の auth_socket）で行う
  - mysql クライアント自身の `SELECT @@version_comment` などが混ざるので取得時に除く
  - **サーバ側のプリペアドステートメントで実行されたクエリは出ない**（確認済み：MySQL 8.0.34・8.4.11、go-sql-driver/mysql）。Go の database/sql で DSN に `interpolateParams=true` が無いと、引数つきのクエリは Prepare → Execute → Close のバイナリプロトコルで実行され、`events_statements_summary_by_digest` には1件も載らない（`events_statements_summary_global_by_event_name` の `statement/com/Execute` の回数にだけ出る）。`db.Prepare` で明示的に準備した文も同じ。Close で破棄されるので `prepared_statements_instances` にも残らない。過去の実測でも、その状態では上位30件のうち SELECT が4件だけで、`interpolateParams=true` を入れた後は18件に増えた
  - → digest に切り替えたら、アプリの主要な SELECT が出ているかを確かめる。`interpolateParams=true` は往復が減るので、それ自体が改善の打ち手にもなる

### MariaDB
- performance_schema は**既定で無効**（有効化に再起動が要る）。digest 表に `QUANTILE_95`・`QUERY_SAMPLE_TEXT` が無い
- → slow log + pt を使う（`QUERY_DIGEST=pt`）。負荷が気になるなら `log_slow_rate_limit`（N 回に1回だけ記録）で間引ける

### PostgreSQL
| | ログ型：`log_min_duration_statement=0` + pgBadger | 集計型：`pg_stat_statements` |
|---|---|---|
| MySQL での相当 | slow log + pt | digest 集計 |
| 負荷 | 大（全クエリをサーバログに書く） | 小（共有メモリで集計） |
| 有効化 | 設定してリロード（再起動不要） | `shared_preload_libraries` に追加して**再起動**、`CREATE EXTENSION pg_stat_statements;` |
| 取れる | 1件ごとの時間・時刻、pgBadger で分布 | 回数、合計・平均・最小・最大・標準偏差、返却行数、共有バッファの hit/read、一時ファイル書き込み |
| 取れない | — | **パーセンタイル**、走査行数（バッファ read で代用）、**実 SQL**（`$1` に正規化される）、時系列 |
| リセット | ログを truncate | `SELECT pg_stat_statements_reset();` |

- 推奨：普段は `pg_stat_statements`、実 SQL や時系列が要るときだけログ型を1回有効にする
- アダプタは `bin/digest/query-pgss.collect.sh`（pre でリセット、post で上位30種を TSV で取る）と `query-pgss.sh`（ミリ秒を秒に直す。`p95` は無いので `mean + 2*stddev`、`rows_examined_avg` は null。`hit_ratio`・`blks_read` を足す）。env.sh は `QUERY_DIGEST=pgss`、`DB_HOSTS`、必要なら `PSQL_CMD`（既定 `sudo -u postgres psql -X`）
- PG 13 未満は列名が `total_time` / `mean_time` など（`_exec_` が無い）

### アプリに組み込まれた DB（SQLite など）
DB サーバのプロセスが無く、クエリはアプリのプロセス内で実行される。MySQL のクエリ集計にも slow log にも出ず、pprof では cgo の呼び出し（Go なら `runtime.cgocall`）や DB ドライバの関数にまとまって見えるだけになる
- まず、アプリ・ドライバにクエリログやトレースの仕組みが用意されていないかを探す（環境変数・設定・コード中のフック）。ある場合は、出力形式に合わせてアダプタ（`query-<tool>.sh`：1行1クエリの記録を fingerprint ごとに回数・合計・平均・p95 にまとめる）を足す。全件を書くので負荷は大きい。深掘りの数回だけ有効にし、通常は止める
- 用意されていなければ、ドライバを包むフック（Go なら `database/sql` のドライバを包んで実行時間を記録する）をアプリに入れる。これもアプリの性能を変えるので、env.sh の変数で切り替えられるようにする
- 軽い代替：pprof の cum で、どのハンドラから DB ドライバが呼ばれているかを見る。クエリの単位では分からないが、重いハンドラは分かる
- DB のファイルが複数に分かれている場合は、ファイルのサイズ・行数の偏りも見る（一部のファイルだけ巨大なことがある）

## HTTP・DB 以外の処理
アクセスログ・クエリ集計・pprof のどれにも出ない負荷がある。アプリのプロセス表（`ps`）とサービス一覧に、アプリ・DB・nginx 以外が動いていないかを見る
- **別のサーバプロセス**（DNS サーバ・キャッシュ・キュー・検索エンジンなど）：多くは統計 API やコマンドで累積カウンタを返す。ベンチの前後に取って差分を見る。orchestrator では `.collect.sh`（`pre|post <host> <出力>`）を `bin/digest/` に置き、`EXTRA_COLLECT` に名前を書くとベンチの前後で呼ばれる。差分の集計は同名のアダプタ（例 `dns-pdns.sh` → `<host>/dns.json`、summary.md の「## dns」）
  - そのプロセスがバックエンドに DB を使っていると、DB のクエリ集計にそのプロセスのクエリが混ざる。ユーザを分けて集計するか、slow log から外す（`long_query_time` をそのユーザだけ上げる）
- **アプリが起動する外部コマンド**（`exec` で呼ぶ CLI など）：プロセスの起動と待ちは pprof の CPU に出ない。アプリ側で1回ごとに `{"cmd","sec","err"}` の JSON を1行ずつログに書き、`LOG_FILES` で回収する（ファイル名を `extcmd.log` にすると `extcmd-jsonl.sh` が `<host>/extcmd.json` と summary.md の「## extcmd」にまとめる）。計測の書き込み自体は軽いが、アプリの変更なので env.sh の変数で止められる形にする

## アクセスログ
- nginx：JSON 形式で `request_time` を含める。alp は `alp json`
- nginx 以外
  - h2o・envoy なども alp の `ltsv` / `json` / `regexp` で読める形式でログを出せば、`access-alp.sh` がそのまま使える
  - どうしても合わない場合は、ログを JSON Lines（method, uri, status, request_time, body_bytes）に変換するアダプタ `access-<tool>.sh` を足す
- URI の正規化は alp の `matching_groups`（雛形は `templates/alp.yml`。競技リポジトリには setup が `config/alp.yml` として置く）で行う。ID を含むパスは必ずまとめる

## プロファイル
- Go：`net/http/pprof` を入れ、ベンチ中に `/debug/pprof/profile?seconds=60` を取る。アプリが複数台なら全台（`PPROF_HOSTS`）
  - flat の上位はランタイム（syscall・GC・malloc）で埋まりやすい。アプリの関数は `main.` パッケージの cum で見る
- Go 以外は言語のプロファイラに差し替え、`profile-<tool>.sh` で `{duration, samples, flat:[], cum:[]}` に変換する（Node: `--cpu-prof`、Ruby: stackprof、Python: py-spy、Rust: perf / pprof-rs など）

## リソース
- sysstat（pidstat）や netdata は入っていないことが多い。netdata は常駐が重く、外部送信の設定にも注意が要る
- `/proc` だけで取れる：`/proc/stat`（CPU）、`/proc/meminfo`、`/proc/net/dev`、`/proc/diskstats`、`/proc/<pid>/stat`（utime+stime・RSS）
- プロセス単位の I/O（`/proc/<pid>/io`）は root が要るので取っていない。必要ならサンプラーを `sudo` で動かす
