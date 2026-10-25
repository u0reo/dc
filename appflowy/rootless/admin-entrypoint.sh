#!/bin/sh -eu
# 公認 /docker-entrypoint.sh の非 root 版。
# 公認版は root 所有の /app/apps/super 配下へ sed -i するため uid 1000 では不可。
# → apps/super 一式(約 12MB)を /tmp tmpfs へコピーしてから注入&起動する。
#   (rootfs は read_only、グループ 0 membership 不要)
: "${APPFLOWY_BASE_URL:?APPFLOWY_BASE_URL is required (compose)}"
: "${APPFLOWY_GOTRUE_BASE_URL:?APPFLOWY_GOTRUE_BASE_URL is required (compose)}"
APPFLOWY_ADMIN_DISABLE_SERVER_ACTIONS=${APPFLOWY_ADMIN_DISABLE_SERVER_ACTIONS:-false}

# ALLOWED_ORIGINS の導出 (公認ロジックと同一意味: 未指定ならBASE_URL,指定なら追加)
if [ -z "$APPFLOWY_ALLOWED_ORIGINS" ] || [ "$APPFLOWY_ALLOWED_ORIGINS" = "__APPFLOWY_ALLOWED_ORIGINS__" ]; then
  APPFLOWY_ALLOWED_ORIGINS="$APPFLOWY_BASE_URL"
else
  case ",$APPFLOWY_ALLOWED_ORIGINS," in
    *",$APPFLOWY_BASE_URL,"*) : ;;
    *) APPFLOWY_ALLOWED_ORIGINS="$APPFLOWY_ALLOWED_ORIGINS,$APPFLOWY_BASE_URL" ;;
  esac
fi

# 重複除去・trim して JSON 配列化 (["a","b"])
ORIGINS_JSON=$(echo "$APPFLOWY_ALLOWED_ORIGINS" | tr ',' '\n' | awk '
  { gsub(/^[ \t]+|[ \t]+$/, ""); if ($0=="") next; if (!seen[$0]++) printf "%s\"%s\"", (n++ ? "," : "") }
  END { }' | sed 's/^/[/; s/$/]/')

APP_DIR=/tmp/afadmin/apps/super
rm -rf /tmp/afadmin
mkdir -p /tmp/afadmin/apps
cp -R /app/apps/super /tmp/afadmin/apps/
# node_modules はコピーせず /app 原版への read-only symlink で解決
rm -rf "$APP_DIR/node_modules" /tmp/afadmin/node_modules
[ -e /app/apps/super/node_modules ] && ln -sfn /app/apps/super/node_modules "$APP_DIR/node_modules"
[ -e /app/node_modules ] && ln -sfn /app/node_modules /tmp/afadmin/node_modules

# Method 1: server.js の allowedOrigins プレースホルダ置換
if [ -f "$APP_DIR/server.js" ] && [ -n "$ORIGINS_JSON" ]; then
  sed -i "s|\[\"__APPFLOWY_ALLOWED_ORIGINS__\"\]|${ORIGINS_JSON}|g" "$APP_DIR/server.js"
fi

# Method 2: プレレンダリング HTML へのクライアント用 config 注入
CONFIG_SCRIPT="<script>window.__APP_CONFIG__={APPFLOWY_BASE_URL:'${APPFLOWY_BASE_URL}',APPFLOWY_GOTRUE_BASE_URL:'${APPFLOWY_GOTRUE_BASE_URL}',APP_VERSION:'${APP_VERSION:-unknown}',APPFLOWY_ALLOWED_ORIGINS:'${APPFLOWY_ALLOWED_ORIGINS}',APPFLOWY_ADMIN_DISABLE_SERVER_ACTIONS:'${APPFLOWY_ADMIN_DISABLE_SERVER_ACTIONS}'};</script>"

HTML_CANDIDATES=""
for f in index login dashboard _not-found; do
  [ -f "$APP_DIR/.next/server/app/$f.html" ] && HTML_CANDIDATES="$HTML_CANDIDATES $APP_DIR/.next/server/app/$f.html"
done
[ -z "$HTML_CANDIDATES" ] && HTML_CANDIDATES=$(find "$APP_DIR/.next" -name '*.html' 2>/dev/null | head -5)
for html_file in $HTML_CANDIDATES; do
  if grep -q "</head>" "$html_file" && ! grep -q "window.__APP_CONFIG__" "$html_file"; then
    sed -i "s|</head>|${CONFIG_SCRIPT}</head>|g" "$html_file"
  fi
done

export APPFLOWY_BASE_URL APPFLOWY_GOTRUE_BASE_URL APP_VERSION APPFLOWY_ALLOWED_ORIGINS APPFLOWY_ADMIN_DISABLE_SERVER_ACTIONS

echo "Starting application on port ${PORT:-3000}... (rootless shim)"
exec node "$APP_DIR/server.js"
