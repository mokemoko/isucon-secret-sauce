#!/usr/bin/env bash
# deploy.sh の2段 (全台の fetch が揃ってから checkout) の確認。ホストごとに別の clone を「サーバ」に見立てる
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT

# fake ssh: コマンド中の app-HOST を app-<host> に差し替えてローカル実行
mkdir "$t/bin"
cat >"$t/bin/ssh" <<EOF2
#!/usr/bin/env bash
while [ "\$1" = -o ]; do shift 2; done
h=\$1; shift; c="\$*"; exec bash -c "\${c//app-HOST/app-\$h}"
EOF2
chmod +x "$t/bin/ssh"
export PATH="$t/bin:$PATH" FETCH_RETRY_WAIT="0 0"
g() { git -C "$t/src" -c user.name=t -c user.email=t@t "$@"; }

git init -q --bare "$t/origin.git"
git clone -q "$t/origin.git" "$t/src" 2>/dev/null
printf 'deploy:\n\t@test ! -e fail\n' >"$t/src/Makefile"
g add . && g commit -qm v1 && g push -q origin HEAD:main
v1=$(g rev-parse HEAD)
for h in h1 h2; do git clone -q "$t/origin.git" "$t/app-$h"; done
echo 'HOSTS="h1 h2"; APP_HOST=h1; REPO_DIR='"$t"'/app-HOST' >"$t/env.sh"
export ENV_FILE="$t/env.sh"
head() { git -C "$t/app-$1" rev-parse HEAD; }

# 1) 成功: 全台が新しい版になり、APP_HOST の sha を出す
echo 2 >"$t/src/x"; g add x; g commit -qm v2; g push -q origin HEAD:main; v2=$(g rev-parse HEAD)
out=$("$root/bin/deploy.sh" origin/main)
[ "$out" = "$v2" ] && [ "$(head h1)" = "$v2" ] && [ "$(head h2)" = "$v2" ] || { echo "FAIL success: $out"; exit 1; }

# 2) h2 の fetch が失敗し続ける → どの台も checkout しない
echo 3 >"$t/src/x"; g commit -qam v3; g push -q origin HEAD:main
git -C "$t/app-h2" remote set-url origin "$t/nowhere.git"
if err=$("$root/bin/deploy.sh" origin/main 2>&1 >/dev/null); then echo "FAIL fetch should fail"; exit 1; fi
echo "$err" | grep -qF 'deploy failed (fetch: h2)' || { echo "FAIL fetch msg: $err"; exit 1; }
[ "$(head h1)" = "$v2" ] || { echo "FAIL h1 checked out despite h2 fetch failure"; exit 1; }

# 3) 1回目の fetch だけ失敗 → 再試行で通る
git -C "$t/app-h2" remote set-url origin "$t/origin.git"
mkdir "$t/gbin"; cat >"$t/gbin/git" <<EOF2
#!/usr/bin/env bash
if [ "\$1" = fetch ] && [ ! -e "$t/fetched-once" ]; then touch "$t/fetched-once"; exit 128; fi
exec $(command -v git) "\$@"
EOF2
chmod +x "$t/gbin/git"
out=$(PATH="$t/gbin:$PATH" "$root/bin/deploy.sh" origin/main)
[ -e "$t/fetched-once" ] && [ "$out" = "$(g rev-parse HEAD)" ] || { echo "FAIL retry: $out"; exit 1; }

# 4) 無い ref → fetch の段で止まる
if err=$("$root/bin/deploy.sh" deadbeef 2>&1 >/dev/null); then echo "FAIL missing ref"; exit 1; fi
echo "$err" | grep -qF 'deploy failed (fetch: h1 h2)' || { echo "FAIL missing ref msg: $err"; exit 1; }

# 5) make deploy が h2 だけ失敗 → どのホストかを出す
touch "$t/app-h2/fail"
if err=$("$root/bin/deploy.sh" origin/main 2>&1 >/dev/null); then echo "FAIL make should fail"; exit 1; fi
echo "$err" | grep -qF 'deploy failed (make deploy: h2)' || { echo "FAIL make msg: $err"; exit 1; }
echo ok
