# ミドルウェア設定の勘所

雛形は `templates/`。ここにはその理由と、構成が違うときの代替を書く。

## nginx
- アクセスログ：JSON 形式で `request_time` を含め、`buffer=64k flush=1s` で書く。最終盤は `access_log off`
- upstream の keepalive は3点セット：`upstream { keepalive N; }`、`proxy_http_version 1.1;`、`proxy_set_header Connection "";`。1つでも欠けると毎回接続し直す
- **スティッキーセッション**（同じユーザーを同じアプリの台へ）：外部モジュール（nginx-sticky-module）は nginx の再ビルドが要り、`sticky` ディレクティブは有料の nginx Plus 専用なので、ISUCON では使えない。標準の `hash` を使う
  ```nginx
  upstream app {
      hash $cookie_session_id consistent;   # cookie 名は問題に合わせる。パスで寄せるなら $request_uri
      server 192.168.0.11:8080;
      server 192.168.0.12:8080;
  }
  ```
  - cookie が無い初回のリクエストは空のキーとして1台に偏る。ログイン直後に寄せ直しが起きてもよい作りにしておく
- 静的ファイル：`location` で nginx が直接返す。`gzip_static on` は事前に `.gz` を置く（`gzip -k`）。`autoindex` は付けない（ディレクトリ一覧が公開される）
- `X-Accel-Redirect`：アプリがヘッダで内部パスを返し、nginx が `internal` の location からファイルを送る。アプリはファイルを読まずに済む
- nginx 以外の前段（h2o、envoy、Caddy など）：アクセスログを alp が読める形（JSON か LTSV）で出す。雛形 `templates/h2o.conf`・`templates/envoy.yml` は LTSV

## MySQL
- 8.0 前提の雛形は `templates/mysqld.cnf`
- `innodb_buffer_pool_size`：データが全部載る大きさが目安。ホストのメモリの 50〜70%
- 耐久性を下げる：`innodb_flush_log_at_trx_commit=2`（コミット毎の fsync をやめる）、`innodb_doublewrite=0`、`disable-log-bin`（8.0 は binlog が既定で有効）。OS クラッシュ時に最大1秒程度失うが、ISUCON の再起動試験はプロセスの正常な再起動なので問題にならない
- `max_connections`：アプリの接続プールの合計より大きく。足りないと `Too many connections`
- バージョン差
  - 5.7：binlog は既定で無効。`query_cache` はあるが書き込みが多いと逆効果（8.0 では削除済み）
  - 8.0.30 以降：`innodb_log_file_size` は非推奨で `innodb_redo_log_capacity`
  - MariaDB：performance_schema が既定で無効。計測は `knowledge/measurement.md`
- 計測：digest 集計を既定にし、slow log は深掘りのときだけ（`knowledge/measurement.md`）

## PostgreSQL
- `shared_buffers`（メモリの 25% 程度）、`effective_cache_size`、`work_mem`（ソート・ハッシュ結合）
- 耐久性を下げる：`synchronous_commit = off`（MySQL の flush_log_at_trx_commit=2 に相当）。`fsync = off` はクラッシュでデータベースが壊れうるので避ける
- 計測は `pg_stat_statements`（`knowledge/measurement.md`）

## OS・systemd
- ファイルディスクリプタ：systemd のユニットに `LimitNOFILE=65535`（`/etc/security/limits.conf` は systemd 配下のサービスには効かない）
- `net.core.somaxconn`・`net.ipv4.tcp_max_syn_backlog`：接続が殺到して取りこぼすとき
- `net.ipv4.ip_local_port_range`・`net.ipv4.tcp_tw_reuse=1`：別ホストの DB へ短い接続を大量に張るとき（まず接続プールで再利用する）
- サービスの起動順：アプリのユニットに `After=mysql.service` など。再起動試験で DB より先に起動して失敗しないように
