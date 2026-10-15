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

### MySQL 8.0：performance_schema の digest 集計（既定）
- アダプタ：`QUERY_DIGEST=psdigest`（`query-psdigest.collect.sh` がベンチ前に `TRUNCATE`、ベンチ後に上位 30 種を取得）
- 確認：`SELECT ENABLED FROM performance_schema.setup_consumers WHERE NAME='statements_digest';` が YES
- 取れる：回数、合計・平均・最大・p95（`QUANTILE_95`）、ロック時間、走査行数、返却行数、インデックス未使用の回数（`SUM_NO_INDEX_USED` + `SUM_NO_GOOD_INDEX_USED`）、ディスク一時テーブル、最も遅かった実 SQL 1件（`QUERY_SAMPLE_TEXT`）
- 制約
  - 正規化 SQL・サンプル SQL は既定 1024 バイトで切られる（`max_digest_length`、`performance_schema_max_sql_text_length`。変更は再起動が要る）
  - 累積値のみで時系列は無い。サンプルは `performance_schema_max_digest_sample_age`（既定60秒）より古いと次の実行で置き換わる
  - `TRUNCATE` には DROP 権限が要る。サーバ上の `sudo mysql`（root の auth_socket）で行う
  - mysql クライアント自身の `SELECT @@version_comment` などが混ざるので取得時に除く
  - **プリペアドステートメントで実行されたクエリが出ないことがある**。Go の database/sql で DSN に `interpolateParams=true` が無いと、引数つきのクエリは Prepare → Execute → Close のバイナリプロトコルで実行される。過去の実測では、その状態で上位30件のうち SELECT が4件だけ（COMMIT と初期化の INSERT が上位）で、`interpolateParams=true` を入れた後は18件に増えた。原因（Execute が digest 表に集計されないのか、別の digest に分かれるのか）は未確認。Close で破棄されるので `prepared_statements_instances` にも残らない
  - → 計測を入れたら、アプリの主要な SELECT が出ているかを確かめる。出ていなければ slow log + pt に切り替える（slow log は COM_STMT_EXECUTE も実 SQL で記録する）。`interpolateParams=true` は往復が減るので、それ自体が改善の打ち手にもなる

### MySQL：slow log + pt-query-digest（深掘り用）
- アダプタ：`QUERY_DIGEST=pt`。slow log のパスを `LOG_FILES` に足す
- 使う場面：遅い実 SQL をパラメータ付きで全件見て EXPLAIN したい、ベンチ中のどの時点で遅くなったかを追いたい
- pt の注意
  - テキスト出力はバイナリを含む INSERT の例をそのまま載せて巨大になる（過去の実測で 1.2MB）。`--output json` を使う
  - バイナリを含むクエリは値を `?` に置換できず fingerprint にバイナリが残ることがある。制御文字を除いて切り詰める
  - 30 秒ごとの進捗表示が stderr に出る。`--progress time,86400` で止める

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
- アダプタを足すなら `query-pgss.collect.sh`（pre でリセット、post で `sudo -u postgres psql -At -F $'\t' -c "SELECT query, calls, total_exec_time, mean_exec_time, max_exec_time, stddev_exec_time, rows, shared_blks_hit, shared_blks_read FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 30"`）と `query-pgss.sh`（時間はミリ秒。`p95` は無いので `max` か `mean + 2*stddev` を入れて、その旨を summary に書く。`rows_examined_avg` は空）
- PG 13 未満は列名が `total_time` / `mean_time` など（`_exec_` が無い）

### アプリに組み込まれた DB（SQLite など）
DB サーバのプロセスが無く、クエリはアプリのプロセス内で実行される。MySQL のクエリ集計にも slow log にも出ず、pprof では cgo の呼び出し（Go なら `runtime.cgocall`）や DB ドライバの関数にまとまって見えるだけになる
- まず、アプリ・ドライバにクエリログやトレースの仕組みが用意されていないかを探す（環境変数・設定・コード中のフック）。ある場合は、出力形式に合わせてアダプタ（`query-<tool>.sh`：1行1クエリの記録を fingerprint ごとに回数・合計・平均・p95 にまとめる）を足す。全件を書くので負荷は大きい。深掘りの数回だけ有効にし、通常は止める
- 用意されていなければ、ドライバを包むフック（Go なら `database/sql` のドライバを包んで実行時間を記録する）をアプリに入れる。これもアプリの性能を変えるので、env.sh の変数で切り替えられるようにする
- 軽い代替：pprof の cum で、どのハンドラから DB ドライバが呼ばれているかを見る。クエリの単位では分からないが、重いハンドラは分かる
- DB のファイルが複数に分かれている場合は、ファイルのサイズ・行数の偏りも見る（一部のファイルだけ巨大なことがある）

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
