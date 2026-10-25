# AppFlowy Cloud

## 公式リファレンス

- docker-compose.yml: https://github.com/AppFlowy-IO/AppFlowy-Cloud/blob/main/docker-compose.yml
- deploy.env: https://github.com/AppFlowy-IO/AppFlowy-Cloud/blob/main/deploy.env
- nginx.conf: https://github.com/AppFlowy-IO/AppFlowy-Cloud/blob/main/nginx/nginx.conf
- appflowy.site.conf: https://github.com/AppFlowy-IO/AppFlowy-Cloud/blob/main/external_proxy_config/nginx/appflowy.site.conf

公式と同じく ai はオプションサービス

## 公式 docker-compose.yml との差分

- MinIO の代わりに単一アカウントの S3 互換ストレージ VersityGW を採用
- worker は 16k ページサイズ版に変更
- 依存の待ち受けを depends_on: condition: service_healthy に変更
- 公開しないサービスは appflowy 内部ネットワークへ閉じ込め
- PostgreSQL (+pgvector) / Redis はホストのものを使用、ソケットで接続
- nginx の代わりに Traefik を使用
- 永続化データをバインドマウントへ変更

## 事前準備

ホストに PostgreSQL (+pgvector) と Redis を入れて以下の設定をしておく

```sh
pg_lsclusters  # 稼働クラスタのバージョンを確認
sudo apt install postgresql-18 postgresql-18-pgvector redis-server
```

`.env` ファイルを作成し、適当な値を作成

### PostgreSQL

```sh
sudo nano /etc/postgresql/18/main/pg_hba.conf
```

PostgreSQL は既定のままでソケット通信が可能

`local all all peer` の上に `local all appflowy scram-sha-256` を追加
(`local all all trust` を追加するとパスワード無しで接続可能)

### Redis

```sh
sudo nano /etc/redis/redis.conf
```

以下の設定を追加し、ソケット通信を有効化

```
unixsocket /run/redis/redis.sock
unixsocketperm 777
```

#### サービスとして有効化

```sh
sudo systemctl reload postgresql
```

```sh
sudo systemctl enable --now postgresql redis-server
```

```sh
redis-cli -s /var/run/redis/redis.sock ping  # PONG
```

#### データベース作成

```sh
set -a; . ./appflowy/.env; set +a  # POSTGRES_PASSWORD を環境変数に取り込む
```

```sh
sudo -u postgres createuser appflowy
sudo -u postgres createdb appflowy -O appflowy
```

パスワード付与と拡張作成を 1 発で。 :'pw' は psql が安全にクォートする

```sh
sudo -u postgres psql -d appflowy -v pw="$POSTGRES_PASSWORD" <<'SQL'
ALTER ROLE appflowy LOGIN SUPERUSER PASSWORD :'pw';
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
SQL
```

確認 (要パスワード)

```sh
psql -U appflowy -d appflowy -h /var/run/postgresql -W -c '\dx'
```

#### 更新時

ソケット接続の仕様上、 **データベースのアップデート後** に各種コンテナの再起動が必須

## セットアップ

- 初回ログイン: `GOTRUE_ADMIN_EMAIL` / `GOTRUE_ADMIN_PASSWORD`
- Admin パネル: `https://appflowy.$DOMAIN/console/`

## Traefik ルーティング (公式 docker/nginx/nginx.conf 相当)

| パス | バックエンド | 備考 |
|---|---|---|
| `/` | web:80 | catch-all |
| `/gotrue` | gotrue:9999 | stripprefix |
| `/ws` | cloud:8000 | WebSocket |
| `/api` | cloud:8000 | body 10M |
| `/api/workspace/{id}/publish` | cloud:8000 | body 1G |
| `/api/chat` `/api/import` | cloud:8000 | body 1G / buffering off |
| `/ai/` | cloud:8000 | stripprefix `/ai` |
| `/scim` | cloud:8000 | 書き換えなし (Enterprise SCIM 用) |
| `/s3-api/` | s3:7000 | stripprefix + Host を `s3:7000` に書換 (presigned URL 用) |
| `/console` | admin_frontend:3000 | 書き換えなし |
