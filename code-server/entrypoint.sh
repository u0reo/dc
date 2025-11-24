#!/bin/sh

# コンテナの初期化(権限等)
/usr/bin/entrypoint.sh --help > /dev/null


# グループを追加
# sudo groupadd -g 101 administrators (_sshとして既に存在するためスキップ)
sudo groupadd -g 65536 docker

# SSH ログイン時には `/etc/group` によって反映されるため、usermod コマンドでも設定
sudo usermod -aG 101 "$USER"
sudo usermod -aG docker "$USER"


# https://docs.docker.com/engine/install/debian/#install-using-the-repository
# docker-ce-cliをインストール

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
# shellcheck disable=SC1091
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \

  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 使うコンポーネントをインストール
sudo apt-get update
sudo apt-get install -y docker-ce-cli gpg shellcheck openssh-server


# wget の HSTS ファイル生成を無効化
echo 'hsts = 0' | sudo tee -a /etc/wgetrc

# Docker サーバーが古いため、API バージョンを環境変数に設定
# https://stackoverflow.com/a/62079819
echo "DOCKER_API_VERSION=\"$("$HOME/terminal.sh" /usr/local/bin/docker version --format '{{.Server.APIVersion}}')\"" | sudo tee -a /etc/environment


# コンテナの環境変数を SSH 使用時にも適用
echo "SSH_PORT=\"$SSH_PORT\"" | sudo tee -a /etc/environment

# SSH の権限チェックを無効化 (ホームディレクトリの権限を変更するのは難しいため)
echo StrictModes no | sudo tee -a /etc/ssh/sshd_config > /dev/null

# SSH サーバーをセットアップ
sudo mkdir -p /run/sshd
sudo /usr/sbin/sshd


# VSCodeを起動
# shellcheck disable=SC3028
/usr/bin/entrypoint.sh \
  --bind-addr 0.0.0.0:7000 \
  --auth none \
  --app-name "[$HOSTNAME] VS Code" \
  --disable-telemetry .
  
