# 競技ごとの設定。Phase1 で `cp env.example.sh env.sh` して埋める
HOSTS="isu1 isu2 isu3"               # ~/.ssh/config の Host 名
APP_HOST=isu1                        # pprof 取得・再起動確認 probe の実行先
REPO_DIR=/home/isucon/webapp         # 各サーバ上の git repo (remote 名 origin)。`make deploy` を Phase1 で用意する
LOG_FILES="/var/log/nginx/access.log /var/log/mysql/mysql-slow.log"  # ベンチ前に truncate、後に回収
BENCH_CMD="echo TODO"                # ベンチ実行コマンド。標準出力の最終行に {"pass":bool,"score":int,...} を出すこと
PPROF_URL=""                         # 例 "http://localhost:6060/debug/pprof/profile?seconds=60" (APP_HOST 上で curl)
PROBE_URLS=""                        # 再起動確認で前後比較する GET URL (APP_HOST 上で curl)
ALP_ARGS="json --config ../config/alp.yml"  # 回収した access.log に対する alp 引数
BLACKBOX_PATHS=""                    # 過去問リハーサル用: ワーカーに読ませないパス (ベンチマーカーのソース等)。本番は空
