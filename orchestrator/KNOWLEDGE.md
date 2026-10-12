# orchestrator の運用知見

この orchestrator（Orca 上の Claude Code 自律チーム、bench lane、ダッシュボード）を動かして分かったこと。
ISUCON 以外の題材に流用するときにも効く内容に限る。ISUCON のチューニング・計測の知見は `../knowledge/`、当日の課題は `ISSUE.md`。

## Orca
- **escalation は Dispatch の外から送れない**。人間（ダッシュボード）からの示唆は `orchestration send --to run:<id> --type status --priority high --subject "[human] ..."` で送り、Coordinator が `check --types` に status を含めて拾う
- **gate-resolve は呼び出し元の Run に束縛される**。外部プロセス（ダッシュボード）からは解決できないので、回答を `[human-gate] <gate_id>` の status メッセージで送り、Coordinator 自身に gate-resolve させる。ダッシュボードは解決されるまで「送信済み・反映待ち」と表示する
- 期限付きゲート：質問文に「HH:MM までに回答が無ければ <既定> 扱い」と書き、期限中は `check --wait --timeout-ms` を 60000 に縮め、期限切れで Coordinator が既定の選択肢で解決する
- **worker-release で解放されるのはターミナルだけ**。worktree と、その中で起動した docker は残る。結論が出たタスクは `docker compose -p <project> down -v` と `orca worktree rm --force` で消す（放置すると Mac のメモリと CPU を食い、他のワーカーのローカル計測を乱す）。user_takeover になったものは retained で残る
- フォルダ信頼：元のリポジトリを信頼済みなら、worker-start の新しい worktree は確認で止まらない。**初回だけ人間が承認する**必要があり、auto モードではエージェントが代理承認できない（分類器が拒否する）

## プロンプト・エージェントの癖
- **シェルが zsh だと未クオートの `$var` は単語分割されない**。リスト値を変数経由で `--deps` などに渡して壊れた（依存なしのダミータスクができた）。値を直接書くか配列・`${=var}` を使う
- 長い作業の後やツールのエラー（英語）の直後は、応答言語が英語に流れやすい
- Coordinator はフェーズを独断で前倒ししがち。前倒しは原則禁止にし、必要なら期限付きゲートで人間に聞かせる
- Implementer の変更前後の比較は、**同じ base（検証直前に取り込んだ origin/main）で**変更なし・変更ありを測らせる。そうしないと他人のマージ分が混ざる
- 0点（fail）の間は「ベスト比」の採否基準が意味をなさない（どの変更も通る）。0点解消を最優先にし、0点が出たら人間判断にする
- 本番でブラックボックスのもの（ISUCON ならベンチマーカー）は、過去問では読めてしまう。ソースを消す・読まない指示・Coordinator による根拠チェックの3段で防ぐ

## bench lane と計測パイプライン
- ベンチは直列（`bin/bench.sh` が `state/bench.lock` を mkdir でロック。macOS に flock は無い）。異常終了で残ったら手で消す
- **計測はツールに依存しない共通スキーマ + アダプタ**（`bin/digest/<kind>-<tool>.sh`、収集が要るものは `.collect.sh`）にする。ツールや DB が変わってもアダプタ1本の追加で済み、AI もダッシュボードもスキーマだけを読めばよい
- AI 向けには上位だけを占有率つきで詰めた `summary.md`（数KB）を作る。生の出力（pt で 1MB 超）を読ませない
- **解析が失敗しても台帳への記録は止めない**（`digest.err` に理由を残す）。`set -e` のスクリプトでは、既に終わったプロセスへの `kill` 失敗でも全体が止まるので `|| true` を付ける
- リモートで常駐させる計測（サンプラー）は、pid ファイル経由で明示的に止める。ssh を切れば止まることには頼らない（docker で試すと止まらなかった）。timeout を後備えにする
- テストは偽の ssh（ホスト名を捨ててローカル実行）で通しの流れを確認する。2台を同じローカル repo に見立てると並列 deploy の git lock が衝突するので、そのケースは deploy を飛ばす

## 道具の落とし穴
- jq：正規表現に制御文字の範囲を書くときは jq の文字列エスケープ1段（`"[\u0001-\u001f]"`）。`\\u` にすると意図しない範囲になり英字が消えた。数値はリテラルの表記（`25.0`）を保つので、比較は `. + 0` でそろえる
- Go：`GOROOT` が別の Go（mise など）を指していると `go tool pprof` や `go run` が壊れる。`env -u GOROOT go ...`
- Chrome 拡張（Claude in Chrome）が使えない・ブロックされるときは、ヘッドレス Chrome の `--screenshot` で表示を確認できる（クリック操作はできない）

## リハーサル
- 過去問の環境は `rehearsal/up.sh` / `down.sh`（タグ単位で作成・削除し、削除後にアカウント全体で残存を確認。TTL で自動 terminate）
- 後片付けで docker のコンテナは消しても、ビルドしたイメージ（`isu-*`）が残る
- 利用量のピーク：Pro プランで 5 時間枠の 76%（約1時間40分の自律運転）。8時間の本番では上限に達する可能性が高い
