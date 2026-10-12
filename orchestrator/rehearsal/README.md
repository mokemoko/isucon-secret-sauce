# リハーサル記録

過去問で orchestrator を通しで動かした記録。過去問ごとの実施状況と、本番との構成差分（＝リハで確かめられないこと）を残す。
作成・削除は `up.sh` / `down.sh`。使い終わったら必ず `down.sh` で消し、残存が無いことを確認する。

## 実施状況

| # | 日付 | 過去問 | 構成 | 結果 | 確かめたこと | 残った課題 |
|---|---|---|---|---|---|---|
| 1 | 2026-10-11 | private-isu（catatsuy_private_isu_amd64_20260524） | t3a.medium ×1、アプリ＋ベンチ同居 | 0 → 70,012（約1時間30分、ベンチ21回）。最初の7回は 0 点 | Phase 1〜改善サイクルの通し、bench lane の直列化、ダッシュボード、人間の示唆・ゲート | `../ISSUE.md` の 1〜13 |
| 2 | 2026-10-12 | ISUCON14（公式 AMI isucon14-20260818100152） | t3a.medium ×1（20GB）、アプリ＋ベンチ同居 | 初期 549・728（実施中） | digest 集計（psdigest）、ssh 越しのリソース取得、`scoring.json`・`insights.md` の運用、マージ待ちの列、決済 API のある問題での Phase 1 | |

## 本番との構成差分

本番（ISUCON 本選）の想定：競技サーバ3台、ベンチはポータルから実行（別ホスト）、マニュアルはポータル、ベンチマーカーのソースは無い。

| 項目 | 本番の想定 | #1 private-isu | #2 ISUCON14 | 差分の影響・本番で注意すること |
|---|---|---|---|---|
| 台数 | 3台 | 1台 | 1台（本番は3台） | 複数台の deploy・`DB_HOSTS`・`PPROF_HOSTS`・台ごとのリソース取得は未検証 |
| スペック | c5.large 程度 | t3a.medium（バースト型） | t3a.medium（本番は c5.large） | スコアの絶対値は比べられない。CPU クレジットの枯渇でスコアがぶれうる |
| ベンチの実行 | ポータル（外部から負荷） | 競技サーバ上で同居実行（`BENCH_CMD` を ssh で） | 競技サーバ上で同居実行（`~/isu-bench.sh` を ssh で） | ベンチが CPU を取り合う。本番の `BENCH_CMD` はポータルの API かジョブ投入になる（Phase 1 で manual から決める） |
| ベンチ結果の取得 | ポータルの表示・API | 標準出力の JSON | ラッパーが標準出力の「結果 pass= スコア=」を JSON にする。標準エラー（内部のデバッグログ）は捨てる | `BENCH_CMD` の出力を `{"pass","score"}` に変換するラッパーが要る |
| マニュアル | ポータル・当日配布 | リポジトリの README・manual | 公式リポジトリの `docs/manual.md`＋`ISURIDE.md`。先頭にリハーサルの注記 | recon が読む場所が変わる |
| ブラックボックス | ソースが無い | AMI に同梱 → up.sh で削除 ＋ `BLACKBOX_PATHS` | AMI にはバイナリ（`~/bench`）だけ。`BLACKBOX_PATHS` で参照禁止 | 本番は `BLACKBOX_PATHS` を空にする |
| 外部 API | 問題による | なし | 決済 API（ベンチが isu1:12345 で立てる。AMI 同梱のモックは停止） | 外部 API の遅延・モックは未検証 |
| DB | 問題による | MySQL 8.0（同居） | MySQL 8.0（同居） | MariaDB・PostgreSQL のアダプタは未検証 |
| ローカル検証 | Docker（問題のリポジトリ次第） | Docker（private-isu の compose） | Docker（エージェントが作る） | ローカルの予測と本番の差（`../ISSUE.md` 11） |

## 準備の手順（RUNBOOK の「開始直後」をリハーサル用に置き換えたもの）
1. `rehearsal/up.sh` で起動する（問題ごとの `AMI`・`VOL_GB`・`BLACKBOX_DIR` は下の表）
2. 前回の `orchestrator/state/`・`env.sh`・競技リポジトリの clone を `~/isucon/archive/<問題>/` に退避する
3. マニュアルを `state/docs/manual-raw.md` に保存し、先頭にリハーサルの注記（台数・ベンチの実行方法・参照禁止のもの）を書く
4. `~/isucon/ssh_config` に up.sh の `ssh_config` を写し、`~/.ssh/config` の先頭に Include を足す（終わったら外す）。`state/docs/hosts.txt` を書く
5. `env.sh` を `env.example.sh` から作り、`HOSTS`・`BENCH_CMD`・`BLACKBOX_PATHS` だけ埋める（Coordinator が開始時に `BLACKBOX_PATHS` を読むため。残りは setup が埋める）
6. 競技リポジトリを空の main にする（リハーサルは `mokemoko/isucon-test` を使い回す）。以降は RUNBOOK の手順 4 の後半から

| 問題 | 起動 | ベンチ |
|---|---|---|
| private-isu | `rehearsal/up.sh`（既定値） | `ssh isu1 /home/isucon/private_isu/benchmarker/bin/benchmarker -u .../userdata -t http://localhost` |
| ISUCON14 | `AMI=ami-0fcf9e8e8675a9ee4 VOL_GB=20 BLACKBOX_DIR= rehearsal/up.sh` | `sudo systemctl disable --now isuride-payment_mock` の後、`rehearsal/isucon14-bench.sh` を `~/isu-bench.sh` に置く（`./bench run --target https://xiv.isucon.net --addr 127.0.0.1:443` の標準出力から JSON を作る） |
