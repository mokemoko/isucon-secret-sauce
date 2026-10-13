# 当日の手順（人間用）

## 事前準備（競技前日まで）
- `~/.ssh/config` に `Include ~/isucon/ssh_config` を追記しておく（当日は ssh_config だけを書けばよい）
- `brew install alp percona-toolkit k6`。`gh auth status` が通ること
- Orca で Claude Code が起動できること。過去問でリハーサル済みであること
- `orchestrator/ISSUE.md` を空にする（表の見出しだけ残す）。残す知見は先に `orchestrator/KNOWLEDGE.md`・`knowledge/` に移す。当日は Coordinator が当日の課題をここに書き足す

## 10:00 開始直後
1. ポータルで AWS 環境を起動する（エージェントに AWS 権限は渡さない）
2. 当日マニュアルの本文を `orchestrator/state/docs/manual-raw.md` に保存する
3. サーバ IP を `orchestrator/state/docs/hosts.txt` に書き、`~/isucon/ssh_config` に `Host isu1` などを書く
4. GitHub に空の **private** リポジトリを作り、手元に clone する。Orca に `repo add` する
   - `orchestrator/env.sh` を `env.example.sh` から作り `HOSTS` だけ書いてから、`orchestrator/bin/deploy-key.sh <owner/repo>` を実行する。各サーバの鍵を書き込み可の deploy key として登録する（書き込み権限を渡す操作なので、エージェントには実行させない。auto モードで止まる）
5. そのリポジトリのワークスペースで Claude Code を起動し、**フォルダ信頼の確認を人間が承認する**（初回だけ表示される。エージェントは代理承認できず、未承認のままだと以後の worker-start が止まる）。そのうえで次を送る：
   「`<isucon-secret-sauce の絶対パス>/orchestrator/prompts/coordinator.md` を読んで Coordinator として開始して」
   （orchestrator 一式と state/ は isucon-secret-sauce 側に置いたまま使う。競技リポジトリにはコピーしない）
6. Coordinator が表示する `go run . -run <run_id> ...` でダッシュボードを起動する
   - チームメンバーと共有する場合は `-addr <Tailscale IP>:9180` にする。**グローバル IP で公開しない**

## 競技中
- 示唆・指示はダッシュボードの入力欄から送る。承認待ちはダッシュボードに出る
- 個々のワーカーの様子は Orca の各ワークスペースで見られる。直接話しかけてもよいが、方針の変更は Coordinator 経由で行う
- `state/bench.lock` が残ってベンチが止まったら、bench.sh が動いていないことを確認してから `rmdir` する
