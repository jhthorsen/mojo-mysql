use Mojo::Base -strict;

use Test::More;
use Mojo::mysql::URL;

# Defaults
my $url = Mojo::mysql::URL->new;
is $url->dsn,      'dbi:mysql:dbname=', 'right data source';
is $url->username, '',        'no username';
is $url->password, '',        'no password';
my $options = {
  utf8 => 1,
  found_rows => 1,
  PrintError => 0,
};
is_deeply $url->options, $options, 'right options';

# Minimal connection string with database
$url = Mojo::mysql::URL->new('mysql:///test1');
is $url->dsn,      'dbi:mysql:dbname=test1', 'right data source';
is $url->username, '',                    'no username';
is $url->password, '',                    'no password';
$options = {
  utf8 => 1,
  found_rows => 1,
  PrintError => 0,
};
is_deeply $url->options, $options, 'right options';

# Minimal connection string with option
$url = Mojo::mysql::URL->new('mysql://?PrintError=1');
is $url->dsn,      'dbi:mysql:dbname=',  'right data source';
is $url->username, '',                   'no username';
is $url->password, '',                   'no password';
$options = {
  utf8 => 1,
  found_rows => 1,
  PrintError => 1,
};
is_deeply $url->options, $options, 'right options';

# Connection string with host and port
$url = Mojo::mysql::URL->new('mysql://127.0.0.1:8080/test2');
is $url->dsn, 'dbi:mysql:dbname=test2;host=127.0.0.1;port=8080',
  'right data source';
is $url->username, '', 'no username';
is $url->password, '', 'no password';
$options = {
  utf8 => 1,
  found_rows => 1,
  PrintError => 0,
};
is_deeply $url->options, $options, 'right options';

# Connection string username but without host
$url = Mojo::mysql::URL->new('mysql://mysql@/test3');
is $url->dsn,      'dbi:mysql:dbname=test3', 'right data source';
is $url->username, 'mysql',               'right username';
is $url->password, '',                    'no password';
$options = {
  utf8 => 1,
  found_rows => 1,
  PrintError => 0,
};
is_deeply $url->options, $options, 'right options';

# Connection string with unix domain socket and options
$url = Mojo::mysql::URL->new(
  'mysql://x1:y2@%2ftmp%2fmysql.sock/test4?PrintError=1');
is $url->dsn,      'dbi:mysql:dbname=test4;host=/tmp/mysql.sock', 'right data source';
is $url->username, 'x1',                                    'right username';
is $url->password, 'y2',                                    'right password';
$options = {
  utf8 => 1,
  found_rows => 1,
  PrintError => 1,
};
is_deeply $url->options, $options, 'right options';

# Connection string with lots of zeros
$url = Mojo::mysql::URL->new('mysql://0:0@/0?PrintError=1');
is $url->dsn,      'dbi:mysql:dbname=0', 'right data source';
is $url->username, '0',               'right username';
is $url->password, '0',               'right password';
$options = {
  utf8 => 1,
  found_rows => 1,
  PrintError => 1,
};
is_deeply $url->options, $options, 'right options';

done_testing();
