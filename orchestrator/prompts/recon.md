# Recon

まず `$ORC/prompts/common.md` を読むこと。

あなたは競技開始直後の調査・準備タスクを1つ担当する。担当タスクは spec に書かれている。
調査結果は、後続の全エージェントが前提知識として読む。**事実と推測を分けて、短く正確に書く。**

## タスク別の成果物

### manual：当日マニュアルの読解 → `$STATE/docs/constraints.md`、`$STATE/docs/scoring.json`、`app-map.md` の採点ルール節
- 入力：人間が保存した `$STATE/docs/manual-raw.md`
- 次の項目を抜き出す
  - 採点ルール（加点・減点・失格条件）
  - ベンチの実行方法
  - サーバ台数・スペック
  - 禁止事項
  - 再起動・追試の条件
- 採点ルールを機械で読める形にして `$STATE/docs/scoring.json` に書く。digest.sh がエンドポイント表に重みを付け、Analyst・Coordinator がボトルネックの優先度に使う
  ```json
  {
    "summary": "採点の要約。重みで表せないルール（売上・完了件数など結果に応じた加点、段階的な負荷上昇など）もここに文章で書く",
    "endpoints": [
      {"method": "GET", "uri": "/api/items", "weight": 1, "note": "成功1件で1点"},
      {"method": "POST", "uri": "^/api/items/[0-9]+/buy$", "weight": 10, "note": "購入成功で10点"},
      {"method": "*", "uri": "^/(css|js|img)/", "weight": 0, "note": "加点なし"}
    ],
    "penalties": "エラー・タイムアウトの減点と失格条件（文章）",
    "consistency": "書き込みの反映をどこまで遅らせてよいか（文章。キャッシュの可否の根拠になる）。記載が無ければ「記載なし」"
  }
  ```
  - `uri` は alp の `matching_groups` と同じ書き方（`^` で始まれば正規表現、それ以外は完全一致）。`weight` は成功1件あたりの相対的な重み。分からないものは載せない（推測で重みを付けない）
- 特に AI 利用、自動化（ポータル操作の自動化）、外部リソースに関する条項を原文のまま引用する。それがレギュレーション（AI によるコード分析・生成は可）より厳しい場合は、worker_done の要約の先頭に `STOP:` と書く

### survey：サーバ構成調査（ホスト1台ごと）→ `$STATE/docs/env.md` の該当ホストの節
- OS、CPU、メモリ、ディスク
- 動いているプロセスとポート
- systemd ユニット
- nginx / DB / アプリの設定ファイルの場所と主要値
- アプリの言語と起動方法
- DB のテーブルと行数
- ログの場所
- **変更しない。読み取りのみ**

### setup：git 化・計測導入・デプロイ経路（survey の後）
1. webapp と主要設定（nginx, mysql, systemd unit）をリポジトリに集める。人間が用意した private リポジトリ（Coordinator のワークスペース。remote は origin）に push する。リポジトリの新規作成・公開設定の変更はしない。各サーバに deploy key を置いて clone する
2. リポジトリ直下の `Makefile` に `deploy` ターゲットを作る。中身は、ビルド、設定ファイルの配置（ホスト名で分岐してよい）、サービス再起動。サーバ上で `make deploy` が冪等に通ること
3. 計測を有効化する
   - nginx のアクセスログを JSON 形式にし、`request_time` を含める。書き込みは `access_log <path> <format> buffer=64k flush=1s;` でバッファリングする（1リクエストごとの write を減らすため。ベンチ後の回収は1秒以上後なので取りこぼさない）
   - クエリの計測は **performance_schema の digest 集計を既定にする**（slow log は有効にしない。負荷が大きいため）。MySQL 8.0 なら `SELECT ENABLED FROM performance_schema.setup_consumers WHERE NAME='statements_digest'` が YES であることを確認し、env.sh に `QUERY_DIGEST=psdigest`・`DB_HOSTS`・`MYSQL_CMD` を書く。`bin/digest/query-psdigest.collect.sh post <host> /tmp/x` が行を返すことを確かめる
   - DB が MySQL 8.0 以外（MariaDB、PostgreSQL など）や、構成が想定と違う場合は、**`$ORC/../knowledge/measurement.md` を読んで**計測方法を選ぶ。足りないアダプタは `$ORC/bin/digest/` に足してよい（`$ORC` の変更はこの setup タスクに限り可）
   - アプリに pprof（または言語相当）を入れる。アプリが動く全台を env.sh の `PPROF_HOSTS` に書く
   - alp 設定（URI の正規化パターン）を作る。nginx の JSON ログ・alp・MySQL の設定は `$ORC/../templates/` の雛形と見比べ、必要な部分だけ取り込む（丸ごと置き換えない）
4. `$ORC/env.sh` を埋める（`env.example.sh` 参照）。BENCH_CMD は manual の結果に従う
   - `PROBE_URLS` は必須。DB のデータを返し、ベンチ以外では変化しない GET を2〜3個（認証が要らないもの。要るなら curl に cookie やヘッダを付けた形で書く）。再起動確認（`bin/restart-check.sh`）が再起動前後の応答を比べてデータの永続化を確かめるのに使い、空だと動かない。APP_HOST 上で `curl -fsS` が通ることを確かめる
5. `$ORC/bin/bench.sh` を1回実行し、`bench.jsonl` に pass 行が出ることを確認する（このタスクに限り本番ベンチ実行可）

### local：ローカル環境構築 → `$STATE/docs/local.md`
- docker compose で、アプリ・DB・nginx をローカルで起動できるようにする
- 本番の DB ダンプか初期データを使う
- worktree ごとに並列起動できるよう、ポートと compose project 名を環境変数で変えられるようにする
- 公開ポートは `127.0.0.1` にだけバインドする（`127.0.0.1:${PORT}:80` の形）。ダッシュボードが使う 9180 番は避ける
- 起動、初期化、停止のコマンドを local.md に書く

### appmap：アプリ仕様の読解 → `$STATE/docs/app-map.md`
- エンドポイント一覧（メソッド、パス、処理概要、触るテーブル）
- 重そうな処理（N+1、全件取得、ロック、外部コマンド、画像処理）
- 初期化処理
- 静的ファイル
- manual の採点ルール（`scoring.json`）と照らして、スコアに効くエンドポイントに印を付ける。scoring.json に載っていないが加点されそうなものは、根拠と一緒に app-map.md に書く（scoring.json は推測で埋めない）
