# ISSUE

リハーサル後の課題一覧。上から順に検討・対応する。
状態：`todo` / `doing` / `done` / `hold`

このファイルは課題管理だけに使う。本選の前日に空にし、当日は当日発生した課題（仕組みの不具合・運用の問題）だけを Coordinator が書き足す。
残すべき知見は空にする前に移す：orchestrator の運用知見 → `KNOWLEDGE.md`、ISUCON のチューニング・計測の知見 → `../knowledge/`（計測は `../knowledge/measurement.md`）

| # | 課題 | 状態 |
|---|---|---|
| 11 | ローカル予測の精度と扱い（リハ#2 で順位付けに使えないと判明） | todo |
| 14 | [リハ#2] setup の rsync・deploy key 生成が auto mode の権限判定で拒否される | done |
| 15 | [リハ#2] ダッシュボード起動コマンドの `$END` が未定義 | done |
| 17 | [リハ#2] 実行中 Dispatch のあるタスクに gate-create できない | done |
| 18 | [リハ#2] 待機中ワーカーの入力欄に下書きがあると send が届かない | done |
| 19 | [リハ#2] check --wait を重ねると2本目が「active actionable waiter」で失敗する | done |
| 20 | [リハ#2] zsh の配列が1始まりで、Coordinator のタスク登録ループの表示名がずれた | done |
| 21 | [リハ#2] PROBE_URLS が空だと restart-check.sh が再起動完了を待たずにベンチを走らせる | done |
| 22 | [リハ#2] Implementer が他の worktree のローカル環境に initialize を誤送信する | done |
| 23 | [リハ#2] EC2 の停止・再開で IP が変わり、複数の設定ファイルを手で直す必要がある | todo |
| 24 | [リハ#2] 終盤にスコアが漂流し、採否判定がノイズに振られた | done |
| 25 | [リハ#2] ローカルの docker イメージ・ボリュームが終了後に残る | done |
| 26 | ダッシュボードのタスクのステータス・並び順が分かりづらい | done |
| 27 | リハ#2 の評価（作業時間の割合、公開解法との比較、自作ベンチの品質） | done |
| 28 | 序盤のマージ待ちの滞留 | done |
| 29 | 打ち手の検討漏れ（反映の猶予を使う打ち手・ホスト分離が後回し） | done |

---

## 11. ローカル予測の精度と扱い
- リハ#2（ISUCON14、k6 の自作ベンチ）：予測の大半が ±1% 前後で、符号が逆のものもあった（chair_last_locations 化：予測 −4.8%、実際 +21%）。誤った予測で通知間隔の延長を退けた。詳細は `rehearsal/README.md` の #2 の評価
- 方向：ローカルは正しさの確認（応答の差分）とスモークに限り、優先度の確信度に予測を入れない（queue.sh）か、重みを下げる。負荷が増えていく仕組みを持たないベンチは、スループットの改善を測れない
- 以下はリハ#1（private-isu）の記録
- 予測と実績の差が −247pt〜+27pt。ローカル MySQL を CPU 0.3 に絞る調整では限界がある
- 案：検証先を本番と同じ AMI の EC2 にする（ワーカーは Mac のまま、起動は人間がスクリプトで）。AMI 複製の可否を Discord で確認する必要がある

## 14. [リハ#2] setup の rsync・deploy key 生成が auto mode の権限判定で拒否される
- 現象：setup ワーカーの isu1→ローカル repo への rsync と、isu1 上の ssh-keygen＋gh repo deploy-key add が auto mode の分類器に拒否され、escalation で停止
- 影響：Phase 1 のクリティカルパス（setup→ベースライン）が人間の対応待ちで止まる
- その場の回避策：判断用タスクにゲートを出し、人間に許可または手動実施を依頼。事前に settings の allow に入れておくか、RUNBOOK の手順に deploy key の用意を入れるのが本筋
- 補足：deploy key は `--allow-write` 付きで登録しようとして「Permission Grant」として止まった。人間が手動で承認して進めた
- 対応（done）：deploy key の登録は人間が開始直後に `bin/deploy-key.sh <owner/repo>` で行う（RUNBOOK の手順4）。setup はサーバ側で webapp を git 化して deploy key で push し、手元は pull する（rsync で手元に写さない）。auto モードの判定は実環境でしか確かめられないので、次のリハーサルで確認する

## 15. [リハ#2] ダッシュボード起動コマンドの `$END` が未定義
- 現象：coordinator.md が `go run . -run <run_id> -end $END` を人間に伝えるが、`$END` をどこにも定義していない。人間はコマンドを受け取れず、ダッシュボードが起動しなかった
- 対応案：競技の終了時刻を人間が `state/docs/` に書く（RUNBOOK の手順に追加）か、ダッシュボードの `-end` を省略可能にする
- 対応（done）：END は coordinator.md に既定値があるが、文章中の値でシェル変数ではなく、リハーサルでは日付も合わない。Coordinator が開始時に `$STATE/end` に書き、ダッシュボードは `-run`・`-end` を省略すると `state/run_id`・`state/end` を読む。人間は `go run .` だけで起動できる。RUNBOOK の手順5で終了時刻を指示に添える

## 17. [リハ#2] 実行中 Dispatch のあるタスクに gate-create できない
- 現象：`gate-create --task <setup>` が `task_not_startable`（Dispatch が active）で拒否された
- 影響：coordinator.md の「question/escalation は gate-create で人間に回す」がそのままでは実行できない
- その場の回避策：判断用のタスク（ワーカーを起動しない）を task-create してそこに gate を付ける。coordinator.md に明記すべき
- 対応（done）：coordinator.md に「ゲートの付け方」を足した（判断用のタスクを作って付け、解決したら completed にする）

## 18. [リハ#2] 待機中ワーカーの入力欄に下書きがあると send が届かない
- 現象：escalation 後に待機していた setup ワーカーへ再開の send を送ったが、入力欄に人間の未送信の下書きが残っていて、ワーカーが通知を取り込まなかった
- 影響：ゲートを解決しても setup が再開せず、Phase 1 のクリティカルパスが止まった
- その場の回避策：人間に下書きを送信してもらう。Coordinator は send 後に worker-read でワーカーが取り込んだかを確認する
- 対応（done）：coordinator.md に、send の後2分以内に worker-read で取り込みを確かめ、取り込んでいなければ人間に知らせる手順を足した。RUNBOOK に「ワーカーの入力欄に書きかけを残さない」を足した

## 19. [リハ#2] check --wait を重ねると2本目が「active actionable waiter」で失敗する
- 現象：バックグラウンドの check --wait が残ったまま別の check --wait を出すと、`already has an active actionable waiter` で失敗する。jq に通していると原因が見えない
- 影響：Coordinator が待機を見失い、メッセージを取りこぼしたように見える
- その場の回避策：check --wait は常に1本だけにする（pgrep で残りを確認）。Run 単位で待機は1本という前提を coordinator.md に書くべき
- 対応（done）：coordinator.md に、待機はフォアグラウンドで1本だけ、jq で捨てない、エラー時は前の待機の期限切れを待つ（pgrep で探して止めない）と書いた。課題24の「他のワーカーの待機を自分のものと誤認した」件もこれで防ぐ

## 20. [リハ#2] zsh の配列が1始まりで、Coordinator のタスク登録ループの表示名がずれた
- 現象：仮説を task-create するループで `names[i]`（0始まりのつもり）を使い、display-name が1件ずつずれた
- 影響：ダッシュボードの表示名が実際の仮説と食い違う（task_title は正しい）
- その場の回避策：対応表を作り直した。common.md の zsh の注意に「配列は1始まり」を足す（bash -c は課題16の理由で使わない）
- 対応（done）：common.md の zsh の注意に「配列の添字は1始まり」を足した

## 21. [リハ#2] PROBE_URLS が空だと restart-check.sh が再起動完了を待たずにベンチを走らせる
- 現象：setup が PROBE_URLS を埋めておらず、snapshot が再起動前後とも空文字の shasum で即一致。reboot から15秒でベンチを開始し、ssh 切断で `bench command failed`（201510-2293ef9）
- 影響：アプリは正常なのに restart-check が fail になり、手順どおりなら不要な revert をするところだった
- その場の回避策：isu1 のサービスが active になるのを待ってから `SKIP_DEPLOY=1 bin/bench.sh HEAD` を手動で再実行。restart-check.sh は PROBE_URLS が空なら失敗させるか、ssh の疎通とサービスの active を待つべき。setup の受け入れ条件に PROBE_URLS を入れる
- 対応（done）：restart-check.sh は PROBE_URLS が空、または再起動前に失敗する URL があれば再起動せずに止まる。再起動後は各ホストに ssh でき `systemctl is-system-running --wait` が running/degraded になるまで待ってから probe を比べる。recon.md の setup で PROBE_URLS を必須にした。`test/restart_check_test.sh` を追加

## 22. [リハ#2] Implementer が他の worktree のローカル環境に initialize を誤送信する
- 現象：ownerchairs が isuride-idx（18091）へ、lastloc が isuride-appnotif（18093）へ、それぞれ initialize を1回誤送信した。idx 側では initialize の失敗が1回出た
- 影響：並列で動く他の Implementer のローカル計測が乱れる。気づかないと誤った予測で採否の順位が狂う
- その場の回避策：被害側のワーカーに知らせて取り直させた。implementer.md / local.md で、自分のポートを環境変数に固定して使う（他のポートに送らない）ことを明記すべき。ポート割り当てを worktree 名から決める仕組みにすると防げる
- 原因：local.md の curl の例にポートが直書き（18080）で、worktree ごとの値は `export` で変える方式だった。Bash の呼び出しごとにシェルが新しくなり export が残らないため、ワーカーが番号を手で打ち直して取り違えた
- 対応（done）：`bin/local-env.sh <name>` が worktree ごとの project 名・ポートを `local/.env` に固定する（compose が自動で読む。name から決め、使用中ならずらす。git の除外に入れる）。recon の local は compose を `local/compose.yml` に置き、ポートを直書きせず `. local/.env &&` で始まるコマンドを書く。implementer.md・localbench.md も同様。`test/local_env_test.sh` を追加

## 23. [リハ#2] EC2 の停止・再開で IP が変わり、複数の設定ファイルを手で直す必要がある
- 現象：一時停止のため EC2 を stop → start したらパブリック IP が変わった。ssh が実際に読むのは `~/isucon/ssh_config`（up.sh が書く `~/isucon/rehearsal/ssh_config` の写し）で、Coordinator が後者だけ直して接続できず数分空費した。queue.sh の「待ち分」も停止時間で膨らみ、順位が待ち時間順になった
- 影響：再開が遅れる。列の順位が意味を失う
- その場の回避策：`~/isucon/ssh_config`・`rehearsal/ssh_config`・`state/docs/hosts.txt` の3つを直した。列は優先度順で手動選択。up.sh で Elastic IP を付けるか、ssh_config を1か所（Include 先）だけにする。queue.sh は一時停止中の時間を待ち分から除く

## 24. [リハ#2] 終盤にスコアが漂流し、採否判定がノイズに振られた
- 現象：matcher 内製化の再起動確認で 15290（012418、再起動直後）→ 以後 11346・10776・11041 と下がった。apprides（10776）は基準（ベスト×0.74=11315）割れで revert したが、revert 後の main も 11041 で、apprides 由来ではなかった可能性が高い。t3a のCPUクレジット、再起動直後かどうか（再起動確認のスコアが高めに出る傾向: 15290）などが疑われるが未検証
- 影響：「ベスト pass スコア × (1−ノイズ)」の基準が、たまたま高く出た1回（再起動確認）に引きずられ、効果のある変更を落としうる
- その場の回避策：なし（終了間際）。ベストは再起動確認のスコアを除いて取る、境界付近は同じ sha で再ベンチしてから判定する、t3a ではなく c5 系で検証する、を検討。また Coordinator が待機プロセスの重複確認を `pgrep "orchestration check --.*wait"` で行い、ワーカーの待機を自分のものと誤認して待機が止まっていた（Run ID を条件に含めて解消）
- データ：同じ sha を続けて測った組の差は、序盤（600点台）で26%、中盤以降はおおむね8%（外れ値で16.5%）。基準に使っていたノイズ幅 0.26 は序盤の値のまま
- 対応（done）：`bin/judge.sh <bench_id>` で判定する。基準は最高点ではなく直近3回の中央値（revert した sha・同じ sha は除く）、ノイズ幅は同じ sha の組の相対差の直近5組の中央値（[0.05, 0.3]）。基準を1回割ったら同じ sha をもう1回測り（retry）、2回続けて割ったら revert。判定は `verdicts.jsonl` に残す。リハ#2 の終盤に当てはめると、CODE=33 修正（11346）と apprides（10776）は即 revert ではなく retry になる。`test/judge_test.sh` を追加
- 残り：Coordinator の待機プロセスの重複確認（`pgrep` が他のワーカーの待機を拾った件）は課題19で扱う

## 25. [リハ#2] ローカルの docker イメージ・ボリュームが終了後に残る
- 現象：終了後、Implementer・localbench が作ったイメージ 43個（`isuride-<task>-app` ×2、`lb-<port>-app`）と匿名ボリューム 20個（mysql のデータ）が残った。コンテナと worktree は消えていた。リハ#1 の `isu-static`・`isu-tmpl`・`isu-lb3` のボリュームも残っていた
- 影響：Mac のディスクを圧迫する（イメージ1個 0.8〜1GB）
- 対応案：compose の down に `--rmi local -v` を付けるよう implementer.md・local.md に書く。Coordinator の終了手順に、`docker compose ls` で残ったプロジェクトを消す処理を入れる
- 対応（done）：停止を `docker compose -f local/compose.yml down -v --rmi local` にした（implementer.md・localbench.md・recon.md・coordinator.md の後始末）。Coordinator の Phase 3 の最後に、`docker compose ls -a` に残った競技リポジトリの project を消す手順を足した

## 26. ダッシュボードのタスクのステータス・並び順が分かりづらい
- 現象：ready は「着手待ち」のつもりだが、表示順が dispatched → ready → completed のようになっていて、流れの順に読めない
- 対応（done）：作業の流れの順（依存待ち → 着手待ち → 実行中 → 判断待ち → 中断 → マージ待ち → 完了 → 失敗）に並べ、日本語の区分名にした（Orca の status は小さく併記）。completed でもマージ待ちの列にあるものは「マージ待ち」に出す。Orca の blocked は未回答のゲートがあるときだけ「判断待ち」、ゲートが無ければ「中断」（ワーカーの停止・失敗。リハ#2 の2件は終了時に worker-stop したもの）

## 27. リハ#2 の評価（done）
- 結果は `rehearsal/README.md` の「#2 の評価」。対応は課題11（自作ベンチ）・28（ベンチ枠の使い方）・29（検討漏れ）に振り分けた

## 28. 序盤のマージ待ちの滞留
- 現象：序盤、Implementer の完了がマージ待ちに積み上がり、ベンチ1回につき1件ずつしか処理できなかった
- 対応案
  - 論点が無くリスクの低いもの、似た対応は、1件ずつではなくまとめて適用して1回のベンチで測る
  - restart check の実施基準を見直し、頻繁な再起動確認を不要にする（例：再起動に関わる変更、または一定件数・一定時間ごとにだけ行う）
- 対応（done）
  - まとめて適用：Analyst が論点の無い定番の変更に `batchable` を付ける。`queue.sh rank` が、先頭が batchable なら batchable・再起動リスクなし・area の重ならないものを最大3件（`BATCH_MAX`）選んで `.batch` に出し、Coordinator が1回のベンチで測る。基準を割ったら全部 revert し、1件ずつ（`cherry-pick -m 1` で）測り直す。ダッシュボードのマージ待ちに 📦 で表示
  - 再起動確認：`restart_risk` を「OS の再起動でしか確かめられないもの」（メモリだけの状態・遅延書き込み・起動時処理・systemd/OS 設定・ファイルの保存先）に絞った。採用のたびには行わず、`restart-pending.tsv` に3件たまるか、最古から45分で1回、と Phase 3 の最終確認
- データ（リハ#2）：ベンチ32回のうち、再起動確認が7回（＋失敗1）、ベースライン3、再開確認1で、4分の1が変更を測らないベンチ。ベンチ枠の稼働は61%で、1回92秒（負荷60秒＋deploy・回収32秒）、ベンチの間の判断の空きは中央値44秒。Implementer の作業は中央値5分で、律速はベンチ枠

## 29. 打ち手の検討漏れ（反映の猶予を使う打ち手・ホスト分離が後回し）
- 公式の講評・上位チームと比べた漏れ（`rehearsal/README.md` の #2 の評価）
  - 座標の反映に3秒の猶予がある（`scoring.json` の consistency に記載）のに、それを使う coordinate の非同期化・バルク INSERT が終了まで未着手
  - 上位チームの最大の伸びは DB の別ホスト化。リハ#2 は1台だったが、最終盤も mysqld が CPU の84%で、3台なら最優先だった
- 対応案：Analyst が毎回 `scoring.json` の consistency（猶予）を読み、それを使い切る打ち手を必ず候補に挙げる。`resources.json` で1プロセスが CPU を占有していて余っているホストがあれば、ホスト分離を候補に挙げる（knowledge/techniques.md の「複数台構成」を参照させる）
- 対応（done）：analyst.md に「毎回の点検」（反映の猶予を使い切る打ち手、クライアントの待ち時間、ホストの割り当て）を足した。ローカル予測が小さい・負というだけで却下済みとみなさない、とも明記。knowledge/techniques.md にクライアントの待ち時間の手法と、DB の別ホスト化の効き目を足した
