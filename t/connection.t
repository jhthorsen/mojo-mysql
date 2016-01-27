use Mojo::Base -strict;
use Test::More;
use Mojo::mysql;

# Defaults
my $mysql = Mojo::mysql->new;
is $mysql->dsn,      'dbi:mysql:dbname=test', 'right data source';
is $mysql->username, '',                      'no username';
is $mysql->password, '',                      'no password';
my $options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 1};
is_deeply $mysql->options, $options, 'right options';

# Minimal connection string with database
$mysql = Mojo::mysql->new('mysql:///test1');
is $mysql->dsn,      'dbi:mysql:dbname=test1', 'right data source';
is $mysql->username, '',                       'no username';
is $mysql->password, '',                       'no password';
$options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 1};
is_deeply $mysql->options, $options, 'right options';

# Connection string with host and port
$mysql = Mojo::mysql->new('mysql://127.0.0.1:8080/test2');
is $mysql->dsn,      'dbi:mysql:dbname=test2;host=127.0.0.1;port=8080', 'right data source';
is $mysql->username, '',                                                'no username';
is $mysql->password, '',                                                'no password';
$options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 1};
is_deeply $mysql->options, $options, 'right options';

# Connection string username but without host
$mysql = Mojo::mysql->new('mysql://mysql@/test3');
is $mysql->dsn,      'dbi:mysql:dbname=test3', 'right data source';
is $mysql->username, 'mysql',                  'right username';
is $mysql->password, '',                       'no password';
$options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 1};
is_deeply $mysql->options, $options, 'right options';

# Connection string with unix domain socket and options
$mysql = Mojo::mysql->new('mysql://x1:y2@%2ftmp%2fmysql.sock/test4?PrintError=1&RaiseError=0');
is $mysql->dsn,      'dbi:mysql:dbname=test4;host=/tmp/mysql.sock', 'right data source';
is $mysql->username, 'x1',                                          'right username';
is $mysql->password, 'y2',                                          'right password';
$options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 1, RaiseError => 0};
is_deeply $mysql->options, $options, 'right options';

# Connection string with lots of zeros
$mysql = Mojo::mysql->new('mysql://0:0@/0?RaiseError=0');
is $mysql->dsn,      'dbi:mysql:dbname=0', 'right data source';
is $mysql->username, '0',                  'right username';
is $mysql->password, '0',                  'right password';
$options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 0};
is_deeply $mysql->options, $options, 'right options';

# Invalid connection string
eval { Mojo::mysql->new('http://localhost:3000/test') };
like $@, qr/Invalid MySQL connection string/, 'right error';

done_testing();
