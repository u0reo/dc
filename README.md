# Dcoker Compose files

デフォルト

```sh
TZ=Asia/Tokyo
DOMAIN=example.com
REPO_PATH=/opt/dc
```

## traefik / adguardhome

`traefik/certificates` 配下のディレクトリをグループ `certs` によって読めるように

```sh
sudo groupadd -g 200 certs
sudo chgrp -R certs "$REPO_PATH/traefik/certificates/certs" "$REPO_PATH/traefik/certificates/private"
sudo chmod -R g+rX  "$REPO_PATH/traefik/certificates/certs" "$REPO_PATH/traefik/certificates/private"
```

ディレクトリに setgid を付け、以降の新規ファイル/サブディレクトリにグループ所有者を継承

```sh
sudo chmod g+s "$REPO_PATH/traefik/certificates/certs" "$REPO_PATH/traefik/certificates/private"
```
