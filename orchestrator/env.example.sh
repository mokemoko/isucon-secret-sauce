# 競技ごとの設定。Phase1 で `cp env.example.sh env.sh` して埋める
HOSTS="isu1 isu2 isu3"               # ~/.ssh/config の Host 名
APP_HOST=isu1                        # 再起動確認 probe の実行先
PPROF_HOSTS="isu1"                   # pprof を取るホスト (アプリが動く全台)。未設定なら APP_HOST
REPO_DIR=/home/isucon/webapp         # 各サーバ上の git repo (remote 名 origin)。`make deploy` を Phase1 で用意する
LOG_FILES="/var/log/nginx/access.log"  # ベンチ前に truncate、後に回収。QUERY_DIGEST=pt のときは slow log も足す
BENCH_CMD="echo TODO"                # ベンチ実行コマンド。標準出力の最終行に {"pass":bool,"score":int,...} を出すこと
PPROF_URL=""                         # 例 "http://localhost:6060/debug/pprof/profile?seconds=60" (PPROF_HOSTS の各台の上で curl)
PROBE_URLS=""                        # 再起動確認で前後比較する GET URL (APP_HOST 上で curl)
ALP_ARGS="json --config ../config/alp.yml"  # 回収した access.log に対する alp 引数
BLACKBOX_PATHS=""                    # 過去問リハーサル用: ワーカーに読ませないパス (ベンチマーカーのソース等)。本番は空
ACCESS_DIGEST=alp                    # 解析アダプタ (bin/digest/<kind>-<tool>.sh)。ログ形式や DB が合わなければアダプタを足して切り替える
QUERY_DIGEST=psdigest                # psdigest: MySQL 8.0 の performance_schema digest 集計 (既定・軽い) / pt: slow log + pt-query-digest (MariaDB、または実 SQL を全件見たいとき)
DB_HOSTS="isu1"                      # DB が動くホスト (psdigest のリセット・取得先)。未設定なら APP_HOST
MYSQL_CMD="sudo mysql"               # DB ホスト上で root 権限の mysql クライアントを起動するコマンド
PROFILE_DIGEST=pprof
RESOURCES_DIGEST=proc                # bin/sample-resources.sh の出力を変換する
RESOURCE_SAMPLING=1                  # 0 でベンチ中のリソース取得を止める
