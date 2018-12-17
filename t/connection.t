use Mojo::Base -strict;
use Test::More;
use Mojo::mysql;
use Mojo::Util 'url_escape';

note 'Defaults';
my $mysql = Mojo::mysql->new;
is $mysql->dsn,      'dbi:mysql:dbname=test', 'right data source';
is $mysql->username, '',                      'no username';
is $mysql->password, '',                      'no password';
my $options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 1};
is_deeply $mysql->options, $options, 'right options';

note 'Without database name';
$mysql = Mojo::mysql->new('mysql://root@');
is $mysql->dsn, 'dbi:mysql', 'right data source';

note 'Minimal connection string with database';
$mysql = Mojo::mysql->new('mysql:///test1');
is $mysql->dsn,      'dbi:mysql:dbname=test1', 'right data source';
is $mysql->username, '',                       'no username';
is $mysql->password, '',                       'no password';
$options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 1};
is_deeply $mysql->options, $options, 'right options';

note 'Connection string with host and port';
$mysql = Mojo::mysql->new('mysql://127.0.0.1:8080/test2');
is $mysql->dsn,      'dbi:mysql:dbname=test2;host=127.0.0.1;port=8080', 'right data source';
is $mysql->username, '',                                                'no username';
is $mysql->password, '',                                                'no password';
$options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 1};
is_deeply $mysql->options, $options, 'right options';

note 'Connection string username but without host';
$mysql = Mojo::mysql->new('mysql://mysql@/test3');
is $mysql->dsn,      'dbi:mysql:dbname=test3', 'right data source';
is $mysql->username, 'mysql',                  'right username';
is $mysql->password, '',                       'no password';
$options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 1};
is_deeply $mysql->options, $options, 'right options';

note 'Connection string with unix domain socket and options';
my $dummy_socket = File::Spec->rel2abs(__FILE__);
$mysql = Mojo::mysql->new("mysql://x1:y2\@@{[url_escape $dummy_socket]}/test4?PrintError=1&RaiseError=0");
is $mysql->dsn,      "dbi:mysql:dbname=test4;mysql_socket=$dummy_socket", 'right data source';
is $mysql->username, 'x1',                                                'right username';
is $mysql->password, 'y2',                                                'right password';
$options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 1, RaiseError => 0};
is_deeply $mysql->options, $options, 'right options';

note 'Mojo::URL object with credentials';
my $url_obj = Mojo::URL->new('mysql://x2:y3@/test5?PrintError=1');
$mysql = Mojo::mysql->new($url_obj);
is $mysql->dsn,      'dbi:mysql:dbname=test5', 'right data source with Mojo::URL object';
is $mysql->username, 'x2',                     'right username';
is $mysql->password, 'y3',                     'right password';
$options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 1, RaiseError => 1};
is_deeply $mysql->options, $options, 'right options';

note 'Connection string with lots of zeros';
$mysql = Mojo::mysql->new('mysql://0:0@/0?RaiseError=0');
is $mysql->dsn,      'dbi:mysql:dbname=0', 'right data source';
is $mysql->username, '0',                  'right username';
is $mysql->password, '0',                  'right password';
$options = {mysql_enable_utf8 => 1, AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 0};
is_deeply $mysql->options, $options, 'right options';

note 'Invalid connection string';
eval { Mojo::mysql->new('http://localhost:3000/test') };
like $@, qr/Invalid MySQL connection string/, 'right error';

note 'Quote fieldnames correctly';
like $mysql->abstract->select("foo", ['binary']),     qr{`binary},       'quoted correct binary';
like $mysql->abstract->select("foo", ['foo.binary']), qr{`foo`.`binary}, 'quoted correct foo.binary';

$mysql = Mojo::mysql->new(dsn => 'dbi:mysql:mysql_read_default_file=~/.cpanstats.cnf');
is $mysql->dsn, 'dbi:mysql:mysql_read_default_file=~/.cpanstats.cnf', 'correct dsn';

$mysql = Mojo::mysql->new({dsn => 'dbi:mysql:mysql_read_default_file=~/.cpanstats.cnf'});
is $mysql->dsn, 'dbi:mysql:mysql_read_default_file=~/.cpanstats.cnf', 'correct dsn';

done_testing;
