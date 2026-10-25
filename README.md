# Dcoker Compose files

デフォルト

```sh
TZ=Asia/Tokyo
DOMAIN=example.com
REPO_PATH=/opt/dc
```

## traefik / adguardhome

`traefik/certificates` の権限をグループ `certs` によって読めるように

```sh
sudo groupadd -g 200 certs
sudo chgrp -R certs "$REPO_PATH/traefik/certificates"
sudo chmod -R g+rX "$REPO_PATH/traefik/certificates"
```

ディレクトリに setgid を付け、以降の新規ファイル/サブディレクトリにグループ所有者を継承

```sh
sudo find "$REPO_PATH/traefik/certificates" -type d -exec chmod g+s {} +
```
