# ベンチマーク実行後にalp,pt-query-digestの結果をhtmlに吐いてslack通知するスクリプト
filename="$(date '+%Y.%m.%d %H:%M:%S').html"
target_path="${NGINX_PUBLIC_DIR}${filename}"
echo "<html><body><pre style=\"font-family: 'Courier New', Consolas, monospace;\">" >> "$target_path"
make alp >> "$target_path"
make pt >> "$target_path"
# make rotate
echo "${BASE_URL}${filename}" | notify_slack -c notify_slack.toml
