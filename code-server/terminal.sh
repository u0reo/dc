#!/bin/sh -eu

# デフォルトは作業ディレクトリを変更
command="cd $PWD; exec bash -l"

# 引数があればそれをコマンドとして実行
if [ $# -gt 0 ]; then
  # shellcheck disable=SC2124
  command="$@"
fi

# shellcheck disable=SC2086
ssh 172.17.0.1 -t -q -p "$SSH_PORT" -i "/home/$USER/.ssh/id_ed25519" $command
