# 当日の手順（人間用）

## 事前準備（競技前日まで）
- `~/.ssh/config` に `Include ~/isucon/ssh_config` を追記しておく（当日は ssh_config だけを書けばよい）
- `brew install alp percona-toolkit k6`。`gh auth status` が通ること
- Orca で Claude Code が起動できること。過去問でリハーサル済みであること

## 10:00 開始直後
1. ポータルで AWS 環境を起動する（エージェントに AWS 権限は渡さない）
2. 当日マニュアルの本文を `orchestrator/state/docs/manual-raw.md` に保存する
3. サーバ IP を `orchestrator/state/docs/hosts.txt` に書き、`~/isucon/ssh_config` に `Host isu1` などを書く
4. GitHub に空の **private** リポジトリを作り、手元に clone する。Orca に `repo add` する
5. そのリポジトリのワークスペースで Claude Code を起動し、次を送る：
   「`<isucon-secret-sauce の絶対パス>/orchestrator/prompts/coordinator.md` を読んで Coordinator として開始して」
   （orchestrator 一式と state/ は isucon-secret-sauce 側に置いたまま使う。競技リポジトリにはコピーしない）
6. Coordinator が表示する `go run . -run <run_id> ...` でダッシュボードを起動する
   - チームメンバーと共有する場合は `-addr <Tailscale IP>:9180` にする。**グローバル IP で公開しない**

## 競技中
- 示唆・指示はダッシュボードの入力欄から送る。承認待ちはダッシュボードに出る
- 個々のワーカーの様子は Orca の各ワークスペースで見られる。直接話しかけてもよいが、方針の変更は Coordinator 経由で行う
- `state/bench.lock` が残ってベンチが止まったら、bench.sh が動いていないことを確認してから `rmdir` する
