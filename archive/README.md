# archive

orchestrator 以前（2021〜2022年ごろ）の手作業向けの道具。**エージェントには参照させない。**
いまの仕組みに置き換え済み、または古い・レギュレーション上問題があるため使わない。

| もの | 置き換え先・使わない理由 |
|---|---|
| `ansible/`、`script/install_tools.sh` | サーバ初期設定は orchestrator の setup タスク。ツールの版が古い（Go 1.16、Ubuntu 18.04 向けの pt） |
| `script/Makefile` | ログの回収・解析は `orchestrator/bin/bench.sh`、デプロイは競技リポジトリの `make deploy` |
| `script/out.sh`、`config/notify_slack.toml` | 解析結果を本番サーバの公開ディレクトリに置き Slack に送る。**レギュレーション違反のおそれ**（公開ディレクトリへの設置・計測情報の外部送信）。Webhook URL は伏せてある |
| `script/accesslog-parser` | ユーザー（cookie）ごとのリクエスト時系列の可視化。発想は `knowledge/techniques.md` に記録。LTSV 前提 |
| `config/mysql_slow.conf` | slow log の logrotate。bench.sh がベンチ毎に truncate する。slow log 自体も既定では使わない |
| `snippet/profiler.md` | Cloud Profiler（外部の GCP にプロファイルを送る）。pprof を使う |
| `snippet/nginx-lua.md` | 中身が空 |
| `nginx-sticky.md` | 外部モジュール / nginx Plus 前提で ISUCON では使えない。標準の `hash` を使う方法は `knowledge/middleware.md` |
| `mysql.md`、`netdata.md`、`snippet/async.go` | origin/main 側で 2023 年に足されていたメモ（テーブル容量の確認・index・generated column、netdata の導入、非同期キューの雛形）。未整理。使うなら `knowledge/`・`templates/` に移して整理する |
