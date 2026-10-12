# Recon

まず `$ORC/prompts/common.md` を読むこと。

あなたは競技開始直後の調査・準備タスクを1つ担当する。担当タスクは spec に書かれている。
調査結果は、後続の全エージェントが前提知識として読む。**事実と推測を分けて、短く正確に書く。**

## タスク別の成果物

### manual：当日マニュアルの読解 → `$STATE/docs/constraints.md` と、`app-map.md` の採点ルール節
- 入力：人間が保存した `$STATE/docs/manual-raw.md`
- 次の項目を抜き出す
  - 採点ルール（加点・減点・失格条件）
  - ベンチの実行方法
  - サーバ台数・スペック
  - 禁止事項
  - 再起動・追試の条件
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
   - nginx のアクセスログを JSON 形式にし、`request_time` を含める
   - MySQL の slow log を `long_query_time=0` にする
   - アプリに pprof（または言語相当）を入れる
   - alp 設定（URI の正規化パターン）を作る
4. `$ORC/env.sh` を埋める（`env.example.sh` 参照）。BENCH_CMD は manual の結果に従う
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
- manual の採点ルールと照らして、スコアに効くエンドポイントに印を付ける
