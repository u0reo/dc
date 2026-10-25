#!/bin/sh -eu
# appflowy_web 用 rootless 起動シム
#
# 方針: 設定を自作し直さず、イメージ付属 /etc/nginx/nginx.conf をそのまま使い、
# sed で最小パッチだけ当てる (イメージ更新で location 構成が変わっても追随する)。
#   1) listen のポート番号 80 → 8080 (非特権ポート化。sysctls 特例は不要になった)
#   2) rootless 化に不可欠な最小限 (読み取り専用 rootfs / uid 1000 対策):
#      user 指令の無効化 / error_log・access_log → /dev/std* / pid・temp → /tmp tmpfs
#   3) 公式 entrypoint の HTML sed 注入の代替: サーバレベル sub_filter 1 行
#      (静的 SPA・SSR レスポンス両方に効く。書込み先は全て /tmp tmpfs)
CFG_DIR=/tmp/appflowy-web
rm -rf "$CFG_DIR"; mkdir -p "$CFG_DIR/body" "$CFG_DIR/proxy" "$CFG_DIR/fastcgi" "$CFG_DIR/uwsgi" "$CFG_DIR/scgi"

: "${APPFLOWY_BASE_URL:?APPFLOWY_BASE_URL is required}"
: "${APPFLOWY_GOTRUE_BASE_URL:?APPFLOWY_GOTRUE_BASE_URL is required}"
: "${APPFLOWY_WS_BASE_URL:?APPFLOWY_WS_BASE_URL is required}"

SRC=/etc/nginx/nginx.conf
NGX="$CFG_DIR/nginx.conf"
[ -f "$SRC" ] || { echo "FATAL: image nginx config not found: $SRC" >&2; exit 1; }
cp "$SRC" "$NGX"

# ---- 2) rootless 化の最小パッチ (該当行が無ければ何もしない) ----
sed -i \
  -e 's|^[[:space:]]*user[[:space:]].*;|# &  # rootless: setuid 不可のためコメント化|' \
  -e 's|error_log[[:space:]]\{1,\}/var/log/nginx/error.log[^;]*;|error_log /dev/stderr notice;|' \
  -e 's|access_log[[:space:]]\{1,\}/var/log/nginx/access.log|access_log /dev/stdout|' \
  -e 's|pid[[:space:]]\{1,\}/var/run/nginx.pid;|pid /tmp/nginx.pid;|' \
  "$NGX"

# temp 群 (設定に無い項目はコンパイルデフォルト = 読取専用 /var/lib/nginx を指すため明示)
# + sub_filter 注入断片を生成し、http ブロック冒頭で一括 include
cat > "$CFG_DIR/rootless.conf" <<'EOT'
    client_body_temp_path /tmp/appflowy-web/body;
    proxy_temp_path       /tmp/appflowy-web/proxy;
    fastcgi_temp_path     /tmp/appflowy-web/fastcgi;
    uwsgi_temp_path       /tmp/appflowy-web/uwsgi;
    scgi_temp_path        /tmp/appflowy-web/scgi;
EOT
{
  printf '    sub_filter "</head>" "<script>window.__APP_CONFIG__={APPFLOWY_BASE_URL:\047%s\047,APPFLOWY_GOTRUE_BASE_URL:\047%s\047,APPFLOWY_WS_BASE_URL:\047%s\047}</script></head>";\n' \
    "$APPFLOWY_BASE_URL" "$APPFLOWY_GOTRUE_BASE_URL" "$APPFLOWY_WS_BASE_URL"
  printf '    sub_filter_once on;\n'
} >> "$CFG_DIR/rootless.conf"
# rootless.conf を http ブロック直後へ挿入 (r = マッチ行の直後にファイル挿入)
grep -Eq '^[[:space:]]*http \{' "$NGX" \
  || { echo "FATAL: 'http {' block not found in $SRC" >&2; exit 1; }
sed -i '/^[[:space:]]*http {/r /tmp/appflowy-web/rootless.conf' "$NGX"

# ---- 1) ポート番号のみを書き換え (.listen 80 が無い構成変更には即失敗する) ----
grep -Eq '^[[:space:]]*listen[[:space:]]+80;' "$NGX" \
  || { echo "FATAL: 'listen 80' not found in $SRC (image config layout changed?)" >&2; exit 1; }
sed -i 's|^[[:space:]]*listen[[:space:]]\{1,\}80;|    listen       8080;|' "$NGX"

# ---- 3) youtube-audio (ストリーミング, proxy_buffering off) への注入無効化 ----
# location 単位の sub_filter はサーバレベル設定を置換するので、絶対一致しない
# パターンのみ含む行を挿入して注入だけを事実上打ち消す (best effort)
sed -i '\|proxy_buffering off;|{i\            sub_filter "~<noscript>afweb-noinject</noscript>" "";
}' "$NGX"

# ---- supervisord: 付属 /etc/supervisor/conf.d/supervisord.conf を sed 最小パッチ ----
# 付属設定のままだと (a) supervisord のログ/pid が root 所有の /var 直下 (read_only では
# 書けない) (b) nginx program がデフォルト /etc/nginx/nginx.conf を読む (上のパッチ済み
# 設定を無視して :80 bind する) ため、この 2 点+ログの stdout 化だけを sed で直す。
SUP_SRC=/etc/supervisor/conf.d/supervisord.conf
[ -f "$SUP_SRC" ] || { echo "FATAL: image supervisord config not found: $SUP_SRC" >&2; exit 1; }
grep -q '^command=/usr/sbin/nginx' "$SUP_SRC" \
  || { echo "FATAL: [program:nginx] command layout changed in $SUP_SRC" >&2; exit 1; }
cp "$SUP_SRC" "$CFG_DIR/supervisord.conf"
sed -i \
  -e 's|logfile=/var/log/supervisor/supervisord.log|logfile=/dev/stdout\nlogfile_maxbytes=0|' \
  -e 's|pidfile=/var/run/supervisord.pid|pidfile=/tmp/supervisord.pid|' \
  -e 's|command=/usr/sbin/nginx -g|command=/usr/sbin/nginx -c /tmp/appflowy-web/nginx.conf -g|' \
  -e 's|stdout_logfile=/var/log/supervisor/[a-zA-Z._]*|stdout_logfile=/dev/stdout|' \
  -e 's|stderr_logfile=/var/log/supervisor/[a-zA-Z._]*|stderr_logfile=/dev/stderr|' \
  -e 's|_maxbytes=10MB|_maxbytes=0|g' \
  "$CFG_DIR/supervisord.conf"
grep -q -- '-c /tmp/appflowy-web/nginx.conf' "$CFG_DIR/supervisord.conf" \
  || { echo "FATAL: nginx -c patch did not apply (command= format changed?)" >&2; exit 1; }
echo "rootless shim: supervisord.conf patched from $SUP_SRC" >&2

exec /usr/bin/supervisord -c "$CFG_DIR/supervisord.conf"
