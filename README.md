# isucon-secret-sauce

ISUCON の本選を、[Orca](https://github.com/stablyai/orca) 上の Claude Code のチームに自律的にチューニングさせるための道具と知見。
人間はコードを書かず、ダッシュボードから示唆と承認を送る。

## 仕組み
- **Coordinator** が仮説の列を管理し、**Recon / Analyst / Implementer / Browser** などのワーカーを worktree ごとに起動する（役割は `orchestrator/prompts/`）
- 本番サーバへのベンチは **bench lane** で直列化し、結果を台帳に残す（`orchestrator/bin/bench.sh`、`lock.sh`、`judge.sh`）
- 計測は、ツールに依存しない共通スキーマとツールごとのアダプタで扱う（`orchestrator/bin/digest.sh`、`bin/digest/`）。alp、pt-query-digest、pg_stat_statements、pprof などを、AI が読める大きさの要約にまとめる
- 進み具合と承認待ちは、Go の標準ライブラリだけで書いたダッシュボードに出す（`orchestrator/dashboard/`）。チームでの共有には EC2 + Caddy の入口を使う（`orchestrator/gateway/`）

## 構成
| 場所 | 中身 |
|---|---|
| `orchestrator/` | 自律チューニングの仕組み。当日の手順は `RUNBOOK.md`、運用の知見は `KNOWLEDGE.md` |
| `orchestrator/rehearsal/` | 過去問の AWS 環境の作成・削除と、リハーサルの記録（`README.md`） |
| `knowledge/` | ISUCON のチューニング・ミドルウェア設定・計測の知見 |
| `templates/` | nginx・MySQL・alp・systemd の設定の雛形 |
| `archive/` | 旧来の手作業向けの道具（現在は使っていない） |

## 必要なもの
- macOS、[Orca](https://github.com/stablyai/orca)、Claude Code
- `gh`、`jq`、Go、`alp`、`percona-toolkit`、`k6`
- リハーサルと入口には AWS アカウント（`rehearsal/up.sh`・`gateway/up.sh` は課金されるリソースを作る。使い終わったら `down.sh` で消す）

テストは偽の ssh を使い、ローカルだけで完結する：

```sh
for t in orchestrator/test/*_test.sh; do bash $t || break; done
```

## 注意
- 個人のチームが自分たちのために作った道具で、ISUCON の運営とは関係ない
- 使う場合は、その回のレギュレーションに従っているかを自分で確かめること（外部リソースの利用、問題・計測情報の扱いなど）
