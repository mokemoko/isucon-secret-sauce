# 当日の手順（人間用）

## 事前準備（競技前日まで）
- `~/.ssh/config` に `Include ~/isucon/ssh_config` を追記しておく（当日は ssh_config だけを書けばよい）
- `brew install alp percona-toolkit k6`。`gh auth status` が通ること（オーケストレータを動かす PC だけでなく、全員）
- ダッシュボードの入口（`orchestrator/gateway/`）を、前日までに一度立てて消し、手順を確かめておく。**自分たちの AWS アカウント**に作る（競技の AWS 環境には作らない）。データは置かず中継するだけだが、問題・計測情報をインターネットから届く入口に通すので、ISUCON2026 のレギュレーションで許されることを事前に確かめる
- オーケストレータと並行して作業する人は、下の「オーケストレータと並行して作業する人へ」を読んでおく。自分のエージェントを使う人は、その約束をエージェントにも渡す
- Orca で Claude Code が起動できること。過去問でリハーサル済みであること
- `orchestrator/ISSUE.md` を空にする（表の見出しだけ残す）。残す知見は先に `orchestrator/KNOWLEDGE.md`・`knowledge/` に移す。当日は Coordinator が当日の課題をここに書き足す

## 10:00 開始直後
1. ポータルで AWS 環境を起動する（エージェントに AWS 権限は渡さない）
2. 当日マニュアルの本文を `orchestrator/state/docs/manual-raw.md` に保存する
3. サーバ IP を `orchestrator/state/docs/hosts.txt` に書き、`~/isucon/ssh_config` に `Host isu1` などを書く。`ForwardAgent no` も書く（`~/.ssh/config` の `Host *` で転送していると、サーバからの GitHub の認証が個人鍵と deploy key で揺れ、fetch が時々失敗する。個人鍵を競技サーバに渡さないためでもある）
   - ベンチがポータルからしか実行できないとき：Orca のブラウザでポータルにログインしたタブを開いたままにし（閉じない・ログアウトしない）、`env.sh` に `BENCH_CMD="bin/portal-bench.sh"`・`PORTAL_PAGE=<そのタブの browserPageId。orca tab list --worktree all --json>`を書く（`PORTAL_TARGET_ID` は空でよい。ポータルの Enqueue ボタンと同じくサーバ一覧の先頭を使う）。`bin/portal-bench.sh targets` が一覧を返すことを確かめる
4. GitHub に空の **private** リポジトリを作り、手元に clone する。Orca に `repo add` する
   - 他のメンバーを collaborator に招待する（Issue・PR を使うため）
   - `orchestrator/env.sh` を `env.example.sh` から作り `HOSTS` だけ書いてから、`orchestrator/bin/deploy-key.sh <owner/repo>` を実行する（env.sh に `GH_REPO` も書かれる）。各サーバの鍵を書き込み可の deploy key として登録する（書き込み権限を渡す操作なので、エージェントには実行させない。auto モードで止まる）
5. 競技リポジトリの main に、Claude Code の sandbox を切る設定を入れて push する（Claude Code の sandbox が有効だと、エージェントが `orchestrator/state/` に書けず、ssh も止まる。ワーカーの worktree にも効くようにリポジトリに入れる。エージェントの sandbox を外す操作なので、auto モードのエージェントには実行させない）
   ```
   mkdir -p .claude && printf '{\n  "sandbox": {\n    "enabled": false\n  }\n}\n' > .claude/settings.json && git add .claude/settings.json && git commit -m "claude: sandbox を無効にする" && git push origin main
   ```
6. そのリポジトリのワークスペースで Claude Code を起動し、**フォルダ信頼の確認を人間が承認する**（初回だけ表示される。エージェントは代理承認できず、未承認のままだと以後の worker-start が止まる）。そのうえで次を送る：
   「`<isucon-secret-sauce の絶対パス>/orchestrator/prompts/coordinator.md` を読んで Coordinator として開始して。END=<競技終了時刻 例 2026-10-31T18:00:00+09:00>」（END を添えなければ coordinator.md の既定値）
   （orchestrator 一式と state/ は isucon-secret-sauce 側に置いたまま使う。競技リポジトリにはコピーしない）
7. Coordinator が run を作ったら（`orchestrator/state/run_id` ができたら）、`cd orchestrator/dashboard && env -u GOROOT go run .` でダッシュボードを起動する（run_id と終了時刻は state から読む）
   - チームメンバーとの共有は `orchestrator/gateway/` で行う（ダッシュボードは 127.0.0.1 のまま。EC2 の Caddy が HTTPS を付けて中継し、入れるのはチームのネットワークの IP からだけ。HTTPS なので、他のメンバーの画面でも OS の通知が出る）。入口は開始前に立ててよい。全員が同じネットワークから使う前提
     ```
     [ALLOW_CIDRS=<出口の IP の範囲>] [SUBNET=<public サブネット>] orchestrator/gateway/up.sh   # URL が出る。ALLOW_CIDRS の既定は実行した PC の IP/32
     orchestrator/gateway/tunnel.sh      # ダッシュボードと同じ PC の別のターミナルで動かし続ける (切れたら張り直す)
     ```
     出口の IP が変わって入れなくなったら `orchestrator/gateway/allow.sh`（今の IP を足す）。**ALLOW_CIDRS に全体（0.0.0.0/0）を入れたり、ダッシュボードを 0.0.0.0・グローバル IP で待ち受けさせたりしない**（問題・計測情報の公開になる）。同じ出口の IP を使う第三者（共用の回線・会社の NAT）からも入れてしまうので、そういう回線では使わない

## 終了後
- `orchestrator/gateway/down.sh` で入口を消し、最後に「clean」と出ることを確かめる（消し忘れても起動から12時間で terminate する）

## 競技中
- 示唆・指示はダッシュボードの入力欄から送る。承認待ちはダッシュボードに出る
  - 新しい承認待ちが出ると通知音が鳴り、タブのタイトルに件数が出る。ブラウザの制約で、ページを開いたら1回どこかをクリックするまで音は鳴らない（「人間の判断待ち」の右上のボタンでオン・オフ）。HTTPS か localhost で開いていれば、別のタブを見ているときに OS の通知も出る
  - 承認待ちへの回答は1件目だけが通る（複数人で見ていても、2人目には「回答済み」と出る）。名前欄を入れておくと、誰が答えたかが全員の画面に出る
- 調査結果（`state/docs/` の constraints.md・env.md・app-map.md など）はダッシュボードの「ドキュメント」（`/docs/`）で読める。manual タスクが `要保存:` と言ってきた文書（ポータルのログインが要るものなど）は、本文を `state/docs/` に保存する
- 個々のワーカーの様子は Orca の各ワークスペースで見られる。直接話しかけてもよいが、方針の変更は Coordinator 経由で行う
- **ワーカーの入力欄に書きかけを残さない**。残っていると Coordinator からの通知がワーカーに入らず、止まる（書いたら送信するか消す）
- ベンチが止まったら、ヘッダの「本番サーバのロック」（`orchestrator/bin/lock.sh status`）で持ち主を見る。持ち主の作業が終わっている（bench.sh が動いていない、手作業の人が終わったと言う）ことを確かめてから `orchestrator/bin/lock.sh break` で消す

## オーケストレータと並行して作業する人へ
オーケストレータに従わず、自分の手や自分のエージェントで改善してよい。二重作業・コンフリクト・計測の取り違えを防ぐため、次の3つだけ守る。競技リポジトリは GitHub の `<owner/repo>`（env.sh の `GH_REPO`）
1. **着手する前に Issue を立てる**。範囲が重なる作業が無いかを先に見る（open の Issue。`orchestrator` ラベルはオーケストレータの作業で、ダッシュボードの「タスク」にも出る）
   ```
   gh issue list -R <owner/repo>
   gh issue create -R <owner/repo> --assignee @me --title "<やること>" --body "範囲: <触るエンドポイント・テーブル・設定ファイル>"
   ```
   オーケストレータは、open の Issue と範囲が重なる仮説を起動しない（5分ごとに同期。ダッシュボードの「人が作業中」に出る）。やめた・終わったら Issue を閉じる
2. **main に直接 push しない。PR に `queue` ラベルを付ける**
   ```
   git push origin <ブランチ>
   gh pr create -R <owner/repo> --label queue --body "範囲: <...>"     # OS の再起動でしか確かめられない変更は --label restart も
   ```
   オーケストレータが列の先頭に積み、本番でベンチを回して採否を決め（他の人の PR と同じベンチでまとめて測ることがある）、結果を PR にコメントする（採用なら main に入り、PR はマージ済みになる。基準を割れば revert される）。main と競合したらコメントが付くので、リベースして push する（ラベルはそのまま）。main に直接入れると、次のベンチでオーケストレータの変更の結果として採否が決まってしまう（`after-bench.sh` が検知して知らせる）
3. **本番サーバに書き込むときはロックを取る**（設定を試す、サービスを再起動する、ポータルからベンチを回す）。ロックの間はオーケストレータのベンチが止まるので短くする。ssh でのログ・`top` などの読み取りは自由
   ```
   LOCK_HOST=isu1 LOCK_NOTE="<名前> <何をするか>" <isucon-secret-sauce>/orchestrator/bin/with-bench-lock.sh <コマンド>
   ```
   この PC の外で、リポジトリが手元に無いときは、同じことを ssh で行う：`ssh isu1 'mkdir /var/tmp/isucon-bench.lock && echo "- $(date +%s) <名前> <何をするか>" >/var/tmp/isucon-bench.lock/owner'` が成功したら取れた（失敗したら誰かが持っている。`ssh isu1 cat /var/tmp/isucon-bench.lock/owner` で持ち主が分かる）。終わったら `ssh isu1 rm -rf /var/tmp/isucon-bench.lock`。本番での変更を残すときは、手で直したままにせず 2. の PR にする
