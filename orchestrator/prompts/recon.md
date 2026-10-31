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
- constraints.md に次の節を必ず作る（マニュアルに記載が無ければ「記載なし」と書く。後のタスクが「無い」のか「読み落とした」のかを区別するため）
  - 追試・再起動の条件（再現スコアの条件、再起動後のデータ、ブラウザでの挙動の確認など）
  - 変更してはいけないもの・止めてはいけないサービス
  - ブラウザでの動作確認の手順（URL・ホスト名・ログインの例）。Browser タスクがこれに従って画面をたどる
  - **参照文書**：本文が参照している別の文書（アプリのマニュアル・仕様書・FAQ・レギュレーション）の一覧と、読んだかどうか。リンク先が当日の公式の文書なら読んで要点を書く。ログインが要る・取得できないものは「未取得」とし、worker_done の要約に `要保存: <文書名>` と書く（人間が `$STATE/docs/` に保存する）。サーバ上・リポジトリ内にある仕様書（survey が見つけたもの）も一覧に入れる
- 特に AI 利用、自動化（ポータル操作の自動化）、外部リソースに関する条項を原文のまま引用する。それがレギュレーション（AI によるコード分析・生成は可）より厳しい場合は、worker_done の要約の先頭に `STOP:` と書く

### survey：サーバ構成調査（ホスト1台ごと）→ `$STATE/docs/env.md` の該当ホストの節
- OS、CPU、メモリ、ディスク
- 動いているプロセスとポート
- systemd ユニット
- nginx / DB / アプリの設定ファイルの場所と主要値
- アプリの言語と起動方法
- DB のテーブルと行数
- ログの場所
- **データと処理の置き場所**：このホストでデータを持つもの・処理を受け持つものを、プロセス・開いているファイルとソケット（`ss -tlnp`・`ls -l /proc/<pid>/fd`）・コンテナ・アプリのコードから洗い出す。定型の構成（nginx・アプリ・MySQL）を前提にしない。DB（MySQL 以外・アプリに組み込まれた DB を含む）、ファイル、キャッシュ、外部 API、DNS、静的ファイル、補助のデーモン。それぞれについて、アプリやミドルウェアが持つ計測の手段（クエリログ・トレースの設定、統計のエンドポイント）があれば書く
- 仕様書・README などの文書がサーバ上にあれば、場所を書く
- 節の最後に「setup 向けの注意」を必ず書く（計測で見えなそうなもの、権限、気づいた罠）
- **変更しない。読み取りのみ**

### setup：git 化・計測導入・デプロイ経路（survey の後）
1. webapp と主要設定（nginx, mysql, systemd unit）をリポジトリに集める。人間が用意した private リポジトリ（Coordinator のワークスペース。remote は origin）に push する。リポジトリの新規作成・公開設定の変更・deploy key の登録はしない（人間が `bin/deploy-key.sh` で登録済み。各サーバから `ssh -T git@github.com` が通る）
   - **サーバ側で git 化して push する**：1台目で webapp のディレクトリに設定ファイルを写し（`etc/nginx/` などリポジトリ内の場所に）、`git init`・commit し、origin を競技リポジトリにして main を push する。origin の main に既に commit がある（人間が入れた `.claude/settings.json` など）ときは、`git fetch origin && git reset origin/main && git checkout origin/main -- .` のように既存の commit の上に積んでから commit・push する（force push しない。既存のファイルを消さない）。手元は `git pull` で受け取る。サーバから手元へ rsync・scp でまとめて写さない（auto モードの判定で止まる）
   - 他のサーバは同じリポジトリを clone して、REPO_DIR に置く
   - 競技リポジトリは private なので、**認証情報を含む設定ファイル（DB のパスワード入りの設定・env ファイルなど）もそのまま入れてよい**（公開しないのでレギュレーションに反しない）。どうしても入れられなかったファイル（auto モードの判定で止まるものなど）は、原本をサーバに残し、**変える値だけを上書きするファイル**をリポジトリに入れて deploy で配置する（systemd の drop-in で `EnvironmentFile=` を後から読ませる、`conf.d/` に上書きの設定を置く、など。`$ORC/../knowledge/middleware.md`）。こうしておけば、DB の移設などで接続先を変えるときも人間の手作業は要らない。原本そのものは deploy で配置しない（サーバ上の原本をそのまま使う）。そのファイルの一覧と「deploy で配置しない」ことを `$STATE/docs/env.md` に書く。後のタスクが別経路で配置して壊すのを防ぐため
2. リポジトリ直下の `Makefile` に `deploy` ターゲットを作る。中身は、ビルド、設定ファイルの配置（ホスト名で分岐してよい）、サービス再起動。サーバ上で `make deploy` が冪等に通ること
3. 計測を有効化する
   - nginx のアクセスログを JSON 形式にし、`request_time` を含める。書き込みは `access_log <path> <format> buffer=64k flush=1s;` でバッファリングする（1リクエストごとの write を減らすため。ベンチ後の回収は1秒以上後なので取りこぼさない）
   - クエリの計測は **slow log（`long_query_time=0`）+ pt-query-digest を既定にする**。アプリがサーバ側のプリペアドステートメントで実行するクエリは performance_schema の digest 集計に出ないため（`$ORC/../knowledge/measurement.md`）。MySQL の設定（`$ORC/../templates/mysqld.cnf` の slow log の節）で有効にし、env.sh に `QUERY_DIGEST=pt`・`DB_HOSTS`・`MYSQL_CMD` を書き、slow log のパスを `LOG_FILES` に足す
   - アプリがテキストプロトコルで実行している（Go なら DSN に `interpolateParams=true` がある）と分かっているなら、軽い digest 集計（`QUERY_DIGEST=psdigest`）でもよい。`SELECT ENABLED FROM performance_schema.setup_consumers WHERE NAME='statements_digest'` が YES であることと、`bin/digest/query-psdigest.collect.sh post <host> /tmp/x` が主要な SELECT を返すことを確かめる
   - `DB_HOSTS` には MySQL が動く**全ホスト**を書く（アプリの DB だけでなく、別のミドルウェアのバックエンドなど別用途の MySQL も）
   - **受け入れ条件**：手順5のベンチの後、`$STATE/analysis/<bench_id>/<host>/queries.json` に、アプリのコードの主要な SELECT（重いエンドポイントが発行するもの）が出ていること。digest 集計にしていて COMMIT・INSERT ばかりで SELECT がほとんど出ない場合は、プリペアドステートメントのクエリが出ていない。slow log に戻す。アプリの DSN はこのタスクでは変えない（ベースラインを変えるため。`interpolateParams` は Analyst が仮説として出す）。slow log の書き込みの負荷が目立つときに digest へ切り替えるのは Analyst の仮説として扱う（切り替えたら主要な SELECT が出ることを確かめる）
   - DB が MySQL 8.0 以外（MariaDB、PostgreSQL など）や、構成が想定と違う場合は、**`$ORC/../knowledge/measurement.md` を読んで**計測方法を選ぶ。足りないアダプタは `$ORC/bin/digest/` に足してよい（`$ORC` の変更はこの setup タスクに限り可）
   - アプリに pprof（または言語相当）を入れる。アプリが動く全台を env.sh の `PPROF_HOSTS` に書く
   - alp 設定（URI の正規化パターン）を作る。nginx の JSON ログ・alp・MySQL の設定は `$ORC/../templates/` の雛形と見比べ、必要な部分だけ取り込む（丸ごと置き換えない）
   - **データと処理の置き場所の表**：`$STATE/docs/env.md` の先頭に、survey の各ホストの節を合わせた表を書く。行はデータ・処理の置き場所ごと、列は「置き場所／ホスト／何が入っているか／今の計測で見えるか（見える・見えない、どの集計に出るか）／見えない場合の手段」。手順5のベンチの後に「見えるか」を実測で埋める
   - **受け入れ条件（全体）**：表のすべての行で「見えるか」が判定済みであること。見えない行があっても setup では深追いしない（Coordinator が measure-extra を並行で起動する）。ただし手段の見当（トレースの設定名、使えるツール）は書く
   - **ブラウザでの確認**：手元のブラウザから APP_HOST の画面を開く方法を env.md の「ブラウザでの確認」節に書く（手元から 443 に直接届くか、`ssh -L` の転送が要るか。アプリが期待するホスト名のパターンと、それを APP_HOST に向ける方法）。Phase 3 の Browser が使う
4. `$ORC/env.sh` を埋める（`env.example.sh` 参照）。BENCH_CMD は manual の結果に従う
   - 人間が既に書いた値（`HOSTS`・`GH_REPO`・`BENCH_CMD` など）は消さない。ベンチがポータルからしか実行できないときは、`BENCH_CMD` は人間が用意する（`$ORC/bin/portal-bench.sh`）。まだ書かれていなければ、ゲートで人間に頼んで待つ。自分でポータルを調べて作らない。あわせて `BENCH_START_LOG` に APP_HOST の nginx のアクセスログのパスを書く（ポータルの列で負荷の開始が遅れても、pprof を負荷の間に取るため）
   - `PROBE_URLS` は必須。DB のデータを返し、ベンチ以外では変化しない GET を2〜3個。URL の ID は**初期データ（`/initialize` で戻るデータ）にあるもの**を使う。ベンチが作ったデータは初期化や DB の移設で消え、再起動確認が「再起動前から失敗」で止まる。`/initialize` を1回呼んだ直後にも通ることを確かめる（認証が要らないもの。要るなら curl に cookie やヘッダを付けた形で書く）。再起動確認（`bin/restart-check.sh`）が再起動前後の応答を比べてデータの永続化を確かめるのに使い、空だと動かない。APP_HOST 上で `curl -fsS` が通ることを確かめる
   - 認証が要る GET しか無ければ、`PROBE_CURL_ARGS` に curl の引数（cookie・ヘッダ）を書く。APP_HOST のシェルで展開されるので、認証情報はサーバ上のコマンド置換（DB から取り出すなど）で得て、手元に持ち出さない。DB を別ホストへ移したら取得元も直す
5. `$ORC/bin/bench.sh` を1回実行し、`bench.jsonl` に pass 行が出ることを確認する（このタスクに限り本番ベンチ実行可）
   - `analysis/<bench_id>/warnings.txt` を見て、`BENCH_WARN_RE` をベンチの出力に合わせる。整合性の警告・エラー（減点や失格につながるもの）の行に当たり、進捗などの通常の行（データの名前に「エラー」などの語を含むものも）や、負荷走行の打ち切りに伴う減点にならない行に当たらないこと。**ベースラインのベンチでほぼ0件になる**ことを確かめる
   - ベンチの出力に減点の件数の行（エラー件数の集計など）があれば、`BENCH_PENALTY_RE` にその件数を取り出す正規表現を書く（`grep -oE` で当たった部分の最初の整数が件数になる）。after-bench.sh は warnings の行数の代わりにこの件数の増減で判定する。`analysis/<id>/penalty.txt` に件数が出ることを確かめる

### measure-extra：見えていないデータ・処理の計測（Phase 2 で並行。setup の後）
- 入力：`$STATE/docs/env.md` の「データと処理の置き場所」の表のうち「見えない」の行（spec に書かれる）
- その行の負荷が本番ベンチの解析（`analysis/<id>/`）に出るようにする。手段の例
  - アプリやドライバが持つクエリログ・トレースの設定を有効にし、回収とアダプタ（`$ORC/bin/digest/<kind>-<tool>.sh` と、回収が要るなら `.collect.sh`）を足す。共通スキーマは `$ORC/bin/digest.sh` の冒頭。アダプタは `$ORC/test/` にテストを足す（`$ORC` の変更はこのタスクに限り可）
  - それが重すぎるなら、pprof の関数・ミドルウェアの統計など軽い代替で、どの処理が重いかを見分けられるようにする
  - `$ORC/bin` の既存のスクリプトを変えるときは、別のファイルに書いてから `mv` で置き換える（その場で編集すると、実行中の bench.sh などを bash が読み違え、台帳に記録されずに終わる）
  - 既存の仕組みを先に使う：DB 以外のミドルウェアの統計は `EXTRA_COLLECT`（ベンチ前後に `.collect.sh` を呼ぶ。`$ORC/env.example.sh`）、アプリが呼ぶ外部コマンドの時間は `extcmd.log`（`bin/digest/extcmd-jsonl.sh` の形式）。使い方は `knowledge/measurement.md` の「HTTP・DB 以外の処理」
- 計測のための設定はアプリの性能を変えうる。負荷の大きい手段（全件のトレース）は、既定で止めておき env.sh の変数で有効にできる形にし、`$STATE/docs/env.md` に使い方と負荷を書く
- アプリ・設定の変更は競技リポジトリのブランチに push し、worker_done の要約に `branch=<branch>` を書く（Coordinator がマージ待ちの列に積み、本番ベンチで測る）。`$ORC` の変更は isucon-secret-sauce 側に直接置く
- 終わったら、表の「見えるか」を更新する

### local：ローカル環境構築 → `$STATE/docs/local.md`
- docker compose で、アプリ・DB・nginx をローカルで起動できるようにする
- 本番の DB ダンプか初期データを使う
- compose ファイルは競技リポジトリの `local/compose.yml` に置く
- worktree ごとに並列起動できるよう、project 名とポートは `local/.env` から読む（compose が自動で読む）。`$ORC/bin/local-env.sh <name>` が `COMPOSE_PROJECT_NAME`・`LOCAL_PORT`（nginx）・`LOCAL_DB_PORT`（DB）・`LOCAL_EXTRA_PORT` を worktree ごとに重ならない値で書く。compose 側は `127.0.0.1:${LOCAL_PORT}:80` のように参照する
- 公開ポートは `127.0.0.1` にだけバインドする。ダッシュボードが使う 9180 番は避ける（local-env.sh は 20000 番台以上を使う）
- 起動、初期化、停止のコマンドを local.md に書く。common.md の「ローカル環境」の形（`. local/.env &&` で始め、ポートは変数）にする

### appmap：アプリ仕様の読解 → `$STATE/docs/app-map.md`
- エンドポイント一覧（メソッド、パス、処理概要、触るテーブル）
- 重そうな処理（N+1、全件取得、ロック、外部コマンド、画像処理）
- 初期化処理
- 静的ファイル
- manual の採点ルール（`scoring.json`）と照らして、スコアに効くエンドポイントに印を付ける。scoring.json に載っていないが加点されそうなものは、根拠と一緒に app-map.md に書く（scoring.json は推測で埋めない）
