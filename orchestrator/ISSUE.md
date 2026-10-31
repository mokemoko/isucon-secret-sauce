# ISSUE

状態：`todo` / `doing` / `done` / `hold`

このファイルは課題管理だけに使う。本選の前日に空にし、当日は当日発生した課題（仕組みの不具合・運用の問題）だけを Coordinator が書き足す。
残すべき知見は空にする前に移す：orchestrator の運用知見 → `KNOWLEDGE.md`、ISUCON のチューニング・計測の知見 → `../knowledge/`（計測は `../knowledge/measurement.md`）

| # | 課題 | 状態 |
|---|---|---|
| 1 | Coordinator の gate-resolve が auto モードの判定で拒否される | doing |
| 2 | 人間が拒否したツール呼び出しが一部実行されていた（worker-start 済み） | done |

---

## 1. gate-resolve が拒否される
- 現象: [human-gate] の回答を受けて gate-resolve を実行すると auto モードの判定で拒否された（10:50頃）
- 影響: 承認済みの仮説 #7 の起動が遅れた
- 回避策: 人間が `!` で gate-resolve を実行した。許可ルールの追加が要る

## 2. 拒否したはずの呼び出しの一部が実行されていた
- 現象: 複数のコマンドをまとめた Bash を人間が拒否したが、worker-start（impl-session）は実行済みだった
- 影響: 再実行が task_not_startable になった。queue add は冪等だったので重複しなかった
- 回避策: 拒否の後は dispatch-show・列で実際の状態を確かめてからやり直す
