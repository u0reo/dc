<?php
  // https://pma.ureo.jp/doc/html/config.html#cfg_blowfish_secret
  $cfg['blowfish_secret'] = sodium_hex2bin($_ENV['SECRET']);
  // https://docs.phpmyadmin.net/ja/latest/config.html#cfg_TitleTable
  $cfg['TitleTable'] = '@DATABASE@ | @PHPMYADMIN@ (@HTTP_HOST@)';
  $cfg['TitleDatabase'] = '@DATABASE@ | @PHPMYADMIN@ (@HTTP_HOST@)';
  $cfg['TitleServer'] = '@HTTP_HOST@ | @PHPMYADMIN@';
?>