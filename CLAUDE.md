# isucon-secret-sauce

ISUCON 本選を、Orca 上の Claude Code チームで自律的にチューニングするための道具と知見。中心は `orchestrator/`。
人間（3人）はコードを書かず、ダッシュボードから示唆と承認を送る。

## 会話
- **ユーザーとの会話はすべて日本語**。コード識別子・技術用語は原文のままでよい。英語のツール出力やエラーの直後も日本語で返す

## 構成
| 場所 | 中身 | 誰が読む |
|---|---|---|
| `orchestrator/` | 自律チューニングの仕組み。`prompts/`（各エージェントの役割）、`bin/`（bench lane・計測・解析）、`dashboard/`（Go 標準ライブラリのみ）、`rehearsal/`（過去問の AWS 環境）、`test/` | 全員 |
| `orchestrator/RUNBOOK.md` | 当日の人間の手順 | 人間 |
| `orchestrator/ISSUE.md` | 課題管理だけ。本選前日に空にし、当日は当日の課題だけを書く | 人間・Coordinator |
| `orchestrator/KNOWLEDGE.md` | orchestrator の運用知見（Orca・プロンプト・計測パイプライン）。ISUCON 以外にも流用できるもの | 改修する人 |
| `knowledge/` | ISUCON のチューニング・計測の知見。`techniques.md`（手法、⚠ は通常業務では採らないもの）、`middleware.md`（設定の勘所）、`measurement.md`（計測と環境ごとの選択肢） | エージェント・人間 |
| `templates/` | nginx・MySQL・alp・systemd の設定とコードの雛形 | setup・Implementer |
| `archive/` | 旧来の手作業向けの道具。**参照しない**（理由は `archive/README.md`） | — |

知見を足すときの振り分け：orchestrator の動かし方 → `orchestrator/KNOWLEDGE.md`、ISUCON の手法・設定・計測 → `knowledge/`、未解決の問題 → `orchestrator/ISSUE.md`。

## orchestrator を変えるとき
- `prompts/*.md` はエージェントがそのまま読む指示書。スクリプトの引数・出力・ファイル配置を変えたら、それを参照しているプロンプトも同時に直す（`grep -rn` で確認）
- 計測は「ツールに依存しない共通スキーマ + アダプタ」（`bin/digest/<kind>-<tool>.sh`、収集が要るものは `.collect.sh`）。スキーマは `bin/digest.sh` の冒頭。解析の失敗でベンチ台帳への記録を止めない
- テスト：`for t in orchestrator/test/*_test.sh; do bash $t || break; done`（偽の ssh でローカル完結。pt-query-digest が無ければ一部 skip）
- ダッシュボード：`cd orchestrator/dashboard && env -u GOROOT go run . -run <run_id> -end <RFC3339>`（`GOROOT` が mise の Go を指していて壊れるため外す）。表示の確認はヘッドレス Chrome の `--screenshot` でできる
- `orchestrator/state/` と `orchestrator/env.sh` は git 管理外（問題情報・計測データを含む）

## 守ること
- レギュレーション（ISUCON2026、`orchestrator/prompts/common.md` に要約）：アプリの実行経路に外部リソースを入れない、問題・計測情報を公開しない（公開リポジトリ・外部サービスへの投稿・本番サーバの公開ディレクトリへの設置は禁止）、指定外のサーバに触らない
- 秘密情報（Webhook URL、鍵、トークン）をコミットしない
- 過去問の AWS 環境を作ったら必ず `orchestrator/rehearsal/down.sh` で消し、残存が無いことを確認する
- 過去問のベンチマーカーの実装は読まない（本番ではブラックボックス）
- エージェントが読む知見（`knowledge/`・`prompts/`）に、過去問の解法を問題名つきで書かない（その問題で再びリハーサルすると答えを渡すことになる）。過去問ごとの評価は `orchestrator/rehearsal/README.md` に書く
