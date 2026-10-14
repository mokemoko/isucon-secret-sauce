# リハーサル記録

過去問で orchestrator を通しで動かした記録。過去問ごとの実施状況と、本番との構成差分（＝リハで確かめられないこと）を残す。
課題番号は ISSUE.md の当時の番号。ISSUE.md は対応後に空にしたので、経緯は git 履歴で見る。
作成・削除は `up.sh` / `down.sh`。使い終わったら必ず `down.sh` で消し、残存が無いことを確認する。

## 実施状況

| # | 日付 | 過去問 | 構成 | 結果 | 確かめたこと | 残った課題 |
|---|---|---|---|---|---|---|
| 1 | 2026-10-11 | private-isu（catatsuy_private_isu_amd64_20260524） | t3a.medium ×1、アプリ＋ベンチ同居 | 0 → 70,012（約1時間30分、ベンチ21回）。最初の7回は 0 点 | Phase 1〜改善サイクルの通し、bench lane の直列化、ダッシュボード、人間の示唆・ゲート | 課題 1〜13（対応済み） |
| 2 | 2026-10-12〜13 | ISUCON14（公式 AMI isucon14-20260818100152） | t3a.medium ×1（20GB）、アプリ＋ベンチ同居 | 初期 534〜717 → ベスト 15,290（再起動確認時）、最終 main 77170bd で 11,041。ベンチ32回、マージ19件（うち1件 revert）。稼働は約1時間35分（途中で EC2 を停止して約4時間中断） | digest 集計（32回すべてで summary.md。欠けたのは ssh 切断の1回だけ）、ssh 越しのリソース取得、`insights.md` の運用、マージ待ちの列、決済 API のある問題での Phase 1、EC2 停止を挟んだ中断・再開、Analyst による DB 集計での律速特定、ブラックボックスの遵守（ベンチの代わりにアクセスログから k6 シナリオを作った）。`scoring.json` はライドの結果で採点される問題のため、エンドポイントの重みが空 | 課題 14〜29（対応済み） |

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
| ローカル検証 | Docker（問題のリポジトリ次第） | Docker（private-isu の compose） | Docker（エージェントが作る） | ローカルの予測は本番の改善率に使えない（#2 の評価） |

## 準備の手順（RUNBOOK の「開始直後」をリハーサル用に置き換えたもの）
1. `rehearsal/up.sh` で起動する（問題ごとの `AMI`・`VOL_GB`・`BLACKBOX_DIR` は下の表）
2. 前回の `orchestrator/state/`・`env.sh`・競技リポジトリの clone を `~/isucon/archive/<問題>/` に退避する
3. マニュアルを `state/docs/manual-raw.md` に保存し、先頭にリハーサルの注記（台数・ベンチの実行方法・参照禁止のもの）を書く
4. `~/isucon/ssh_config` に up.sh の `ssh_config` を写し、`~/.ssh/config` の先頭に Include を足す（終わったら外す）。`state/docs/hosts.txt` を書く
5. `env.sh` を `env.example.sh` から作り、`HOSTS`・`BENCH_CMD`・`BLACKBOX_PATHS` だけ埋める（Coordinator が開始時に `BLACKBOX_PATHS` を読むため。残りは setup が埋める）
6. 競技リポジトリを空の main にする（リハーサルは `mokemoko/isucon-test` を使い回す。前回の deploy key は消す）。`bin/deploy-key.sh mokemoko/isucon-test` を実行する。以降は RUNBOOK の手順 5 から
7. 他の過去問は matsuu/aws-isucon の公開 AMI（ISUCON5予選〜14）で起動できる。ベンチの実行方法は各ディレクトリの README
8. 途中で中断するときは `rehearsal/pause.sh stop`、再開は `rehearsal/pause.sh start`（IP の付け替えと、マージ待ちの待ち時間の補正をする）

| 問題 | 起動 | ベンチ |
|---|---|---|
| private-isu | `rehearsal/up.sh`（既定値） | `ssh isu1 /home/isucon/private_isu/benchmarker/bin/benchmarker -u .../userdata -t http://localhost` |
| ISUCON14 | `AMI=ami-0fcf9e8e8675a9ee4 VOL_GB=20 BLACKBOX_DIR= rehearsal/up.sh` | `sudo systemctl disable --now isuride-payment_mock` の後、`rehearsal/isucon14-bench.sh` を `~/isu-bench.sh` に置く（`./bench run --target https://xiv.isucon.net --addr 127.0.0.1:443` の標準出力から JSON を作る） |
| ISUCON13 | `AMI=ami-006d211cb716fe8a0 APP_COUNT=2 TYPE=c6a.large BENCH_TYPE=c6a.large BLACKBOX_DIR= rehearsal/up.sh`（AMI は [matsuu/aws-isucon](https://github.com/matsuu/aws-isucon)） | isu1・isu2 の `~/env.sh` の `ISUCON13_POWERDNS_SUBDOMAIN_ADDRESS` を各自のプライベート IP にして `sudo ~/webapp/pdns/init_zone.sh`・`systemctl restart isupipe-go`。bench ホストはアプリ一式を `disable --now` し、`/etc/hosts` に isu1・isu2 を書き、`rehearsal/isucon13-bench.sh` を `~/isu-bench.sh` に置く。`BENCH_CMD="ssh bench /home/isucon/isu-bench.sh"` |

## #2 の評価（ISUCON14）

### 作業時間の割合
稼働は約1時間40分（10:39〜11:38、15:53〜16:33。間の中断を除く）。

| 区分 | 時間・割合 | 所見 |
|---|---|---|
| Phase 1 | 開始から最初のベンチまで18分、ベースライン3回の終了まで22分 | setup が17分で律速。うち3分は deploy key の承認待ち（課題14）。localbench の初期構築（22分）は並行 |
| ベンチ枠 | ベンチ区間80分のうち、稼働は49分（61%） | 1回は平均92秒（負荷走行60秒＋deploy・回収32秒）。ベンチの間の空きは中央値44秒（Coordinator の判断） |
| ベンチの内訳 | 32回：変更の測定20、再起動確認7（＋失敗1）、ベースライン3、再開確認1 | **4分の1が変更を測らないベンチ**。再起動確認は変更2〜3件に1回 |
| Implementer | 作業時間は中央値5分。着手待ちは最大20分以上（同時3件の上限）、マージ待ちは中央値6分・最大24分 | 実装は速く、律速はベンチ枠。序盤（11:06〜11:35）に完了した7件は、マージまで0〜20分待った |
| 人間待ち | ゲート3件で計約5分 | 小さい |

→ 改善点：ベンチ1回に複数の変更を載せる、再起動確認を減らす（課題28）。判断の空き（44秒）と deploy・回収（32秒）も、1回あたり約1分短縮の余地がある。

### 公開されている解法との比較
参照：[公式の解説と講評](https://isucon.net/archives/58869617.html)、[LayerX の参加記](https://zenn.dev/layerx/articles/3bd55b77e047c4)（本番中 48,615点）。

| 打ち手 | 公式・上位チーム | リハ#2 |
|---|---|---|
| インデックス、owner/chairs の絞り込み、nearby-chairs の N+1、chair の最新位置・総距離のテーブル化 | 序盤の定番 | すべて実施 |
| マッチング：一括・最寄り優先 | 中盤の本体 | 実施（序盤に約2倍） |
| interpolateParams、トークンのオンメモリキャッシュ、matcher のアプリ内化 | 中〜終盤 | 実施 |
| **DB を別ホストへ分離** | LayerX で 5,578 → 10,221 と最大の伸び | 1台構成のため対象外。ただし最終盤も mysqld が CPU の84%で、本番の3台なら最優先の打ち手だった |
| **通知の間隔を伸ばす**（30 → 100 → 300 → 1000ms、通知をまとめて返す） | 上位の主要な伸び | 100ms で止めた。localbench で 200ms が −26% と出たため。localbench の椅子のループの想定が実際と違っていた可能性が高い |
| **coordinate の非同期化・バルク INSERT**（座標反映の3秒の猶予を使う） | 公式の想定解 | 終了時に未着手（`coord-async` が ready のまま）。猶予は `scoring.json` の consistency に書かれていた |
| ライドの完全終了を記録してマッチングに使う、遠すぎる組み合わせを見送る | 中盤 | 一部（COMPLETED の扱いは Analyst が特定） |
| 決済の Idempotency-Key、SSE | 必須ではない | 未実施で妥当 |

→ 検討漏れは2系統。(1) 反映の猶予（3秒）を使い切る打ち手が後回しになった、(2) localbench の誤った予測で、有効な打ち手（通知間隔）を退けた。

### 自作ベンチ（localbench）の品質
- 作り：本番のアクセスログから k6 のシナリオを作った（ベンチマーカーは読まずに作成）。構成比は本番との乖離が約8%まで近づいた。ユーザー数・椅子数は固定（負荷が増えていく仕組みは無い）
- 予測と実際（マージした変更、前のベンチ比。実際の値も、同じコードで約26%の揺れを含む）

| 変更 | 予測 | 実際 |
|---|---|---|
| 認証キャッシュ | +39% | +6%（再起動後 −2%） |
| chair_last_locations 化 | −4.8% | **+21%** |
| app/notification の往復削減 | −4% | +5% |
| nginx keepalive | −0.1% | **+16%** |
| matcher のアプリ内化 | +1.2% | +2%（再起動後 +23%） |
| nearby-chairs 窓関数の除去 | −0.5% | +3% |
| retry_after_ms 100 | （200 で −26%） | +5.5% |

- 評価：**順位付けには使えなかった**。大半の予測が ±1% 前後に固まり、符号が逆のものもある。スコアの揺れ（CV 約13%）が大きく、負荷が固定のため「速くなると負荷が増えて得点が伸びる」動きを再現できない。一方で、`verify.sh` による応答の差分の検査は、正しさの確認として役に立った
- 対応：課題11に統合する（予測の扱いを見直す）
