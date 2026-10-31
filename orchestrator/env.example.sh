# 競技ごとの設定。Phase1 で `cp env.example.sh env.sh` して埋める
HOSTS="isu1 isu2 isu3"               # ~/.ssh/config の Host 名
APP_HOST=isu1                        # 再起動確認 probe の実行先
GH_REPO=""                           # 競技リポジトリ (owner/repo)。bin/deploy-key.sh が書く。bin/team.sh (Issue・PR での他の人との連携) が使う
LOCK_HOST=""                         # 本番サーバのロック (bin/lock.sh) を置くホスト。未設定なら APP_HOST。全員が ssh できるホストにする
LOCK_PATH=""                         # ロックのディレクトリ。未設定なら /var/tmp/isucon-bench.lock (再起動で消えない場所)
PPROF_HOSTS="isu1"                   # pprof を取るホスト (アプリが動く全台)。未設定なら APP_HOST
REPO_DIR=/home/isucon/webapp         # 各サーバ上の git repo (remote 名 origin)。`make deploy` を Phase1 で用意する
LOG_FILES="/var/log/nginx/access.log /var/log/mysql/mysql-slow.log"  # ベンチ前に truncate、後に回収。QUERY_DIGEST=pt (既定) のときは slow log も入れる
BENCH_CMD="echo TODO"                # ベンチ実行コマンド。標準出力の最終行に {"pass":bool,"score":int,...} を出すこと
PPROF_URL=""                         # 例 "http://localhost:6060/debug/pprof/profile?seconds=60" (PPROF_HOSTS の各台の上で curl)
PPROF_APP_RE=""                      # summary.md の cum 上位に出すアプリの関数 (jq の正規表現)。空なら ^main\. 。main 以外のパッケージにアプリがあるときに書く
PROBE_URLS=""                        # 必須。再起動確認で前後比較する GET URL (APP_HOST 上で curl)。空だと restart-check.sh が動かない
PROBE_CURL_ARGS=""                   # 任意。PROBE の curl に足す引数 (APP_HOST のシェルで展開。cookie はサーバ側のコマンド置換で取る)
ALP_ARGS="json --config <競技リポジトリの絶対パス>/config/alp.yml"  # 回収した access.log に対する alp 引数 (雛形は templates/alp.yml)
BLACKBOX_PATHS=""                    # ワーカーに読ませないパス (ベンチマーカーのソース等)。空なら制限なし
BENCH_WARN_RE="WARN|ERROR"           # bench.txt のうち警告・エラーとして数える行 (grep -E)。問題の出力形式に合わせて setup が直す (ベースラインでほぼ0件になること)
BENCH_PENALTY_RE=""                  # ベンチが減点の件数を出す行 (grep -oE。当たった部分の最初の整数を件数とする。例 "[Ee]rrors?[ :=]+[0-9]+")。あれば after-bench.sh は warnings の代わりにこれの増減を見る
ACCESS_DIGEST=alp                    # 解析アダプタ (bin/digest/<kind>-<tool>.sh)。ログ形式や DB が合わなければアダプタを足して切り替える
QUERY_DIGEST=pt                      # pt: slow log + pt-query-digest (既定。プリペアドステートメントのクエリも出る) / psdigest: MySQL 8.0 の performance_schema digest 集計 (軽いが、サーバ側のプリペアドステートメントのクエリは出ない)
DB_HOSTS="isu1"                      # MySQL が動く全ホスト (psdigest のリセット・取得先。別用途の MySQL も含め、役割を移しても外さない)。未設定なら APP_HOST
MYSQL_CMD="sudo mysql"               # DB ホスト上で root 権限の mysql クライアントを起動するコマンド
PROFILE_DIGEST=pprof
EXTRA_COLLECT=""                     # 追加の計測 (空白区切り)。bin/digest/<名前>.collect.sh をベンチ前後に EXTRA_COLLECT_HOSTS の各台で呼ぶ。例 dns-pdns: PowerDNS の統計 API の差分 → <host>/dns.json (PDNS_API_KEY が必須、PDNS_API_URL)
EXTRA_COLLECT_HOSTS=""               # 未設定なら APP_HOST
RESOURCES_DIGEST=proc                # bin/sample-resources.sh の出力を変換する
RESOURCE_SAMPLING=1                  # 0 でベンチ中のリソース取得を止める
