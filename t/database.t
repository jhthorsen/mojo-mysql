use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Mojo::IOLoop;
use Mojo::mysql;

# Defaults
my $mysql = Mojo::mysql->new;
is $mysql->dsn,      'dbi:mysql:dbname=test', 'right data source';
is $mysql->username, '',                      'no username';
is $mysql->password, '',                      'no password';
is_deeply $mysql->options, {mysql_enable_utf8 => 1, AutoCommit => 1, PrintError => 0, RaiseError => 1}, 'right options';

# Minimal connection string
$mysql = Mojo::mysql->new('mysql:///test1');
is $mysql->dsn,      'dbi:mysql:dbname=test1', 'right data source';
is $mysql->username, '',                       'no username';
is $mysql->password, '',                       'no password';
is_deeply $mysql->options, {mysql_enable_utf8 => 1, AutoCommit => 1, PrintError => 0, RaiseError => 1}, 'right options';

# Connection string with host and port
$mysql = Mojo::mysql->new('mysql://127.0.0.1:8080/test2');
is $mysql->dsn,      'dbi:mysql:dbname=test2;host=127.0.0.1;port=8080', 'right data source';
is $mysql->username, '',                                                'no username';
is $mysql->password, '',                                                'no password';
is_deeply $mysql->options, {mysql_enable_utf8 => 1, AutoCommit => 1, PrintError => 0, RaiseError => 1}, 'right options';

# Connection string username but without host
$mysql = Mojo::mysql->new('mysql://root@/test3');
is $mysql->dsn,      'dbi:mysql:dbname=test3', 'right data source';
is $mysql->username, 'root',                   'right username';
is $mysql->password, '',                       'no password';
is_deeply $mysql->options, {mysql_enable_utf8 => 1, AutoCommit => 1, PrintError => 0, RaiseError => 1}, 'right options';

# Connection string with unix domain socket and options
$mysql = Mojo::mysql->new('mysql://x1:y2@%2ftmp%2fmysql.sock/test4?PrintError=1&RaiseError=0');
is $mysql->dsn,      'dbi:mysql:dbname=test4;host=/tmp/mysql.sock', 'right data source';
is $mysql->username, 'x1',                                          'right username';
is $mysql->password, 'y2',                                          'right password';
is_deeply $mysql->options, {mysql_enable_utf8 => 1, AutoCommit => 1, PrintError => 1, RaiseError => 0}, 'right options';

# Connection string with lots of zeros
$mysql = Mojo::mysql->new('mysql://0:0@/0?RaiseError=0');
is $mysql->dsn,      'dbi:mysql:dbname=0', 'right data source';
is $mysql->username, '0',                  'right username';
is $mysql->password, '0',                  'right password';
is_deeply $mysql->options, {mysql_enable_utf8 => 1, AutoCommit => 1, PrintError => 0, RaiseError => 0}, 'right options';

# Invalid connection string
eval { Mojo::mysql->new('http://localhost:3000/test') };
like $@, qr/Invalid MySQL connection string/, 'right error';

$mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
ok $mysql->db->ping, 'connected';

# Blocking select
is_deeply $mysql->db->query('select 1 as one, 2 as two, 3 as three')->hash, {one => 1, two => 2, three => 3},
  'right structure';

# Non-blocking select
my ($fail, $result);
my $db = $mysql->db;
is $db->backlog, 0, 'no operations waiting';
$db->query(
  'select 1 as one, 2 as two, 3 as three' => sub {
    my ($db, $err, $results) = @_;
    $fail   = $err;
    $result = $results->hash;
    Mojo::IOLoop->stop;
  }
);
is $db->backlog, 1, 'one operation waiting';
Mojo::IOLoop->start;
is $db->backlog, 0, 'no operations waiting';
ok !$fail, 'no error' or diag "err=$fail";
is_deeply $result, {one => 1, two => 2, three => 3}, 'right structure';

# Concurrent non-blocking selects
($fail, $result) = ();
Mojo::IOLoop->delay(
  sub {
    my $delay = shift;
    my $db    = $mysql->db;
    $db->query('select 1 as one' => $delay->begin);
    $db->query('select 2 as two' => $delay->begin);
    $db->query('select 2 as two' => $delay->begin);
  },
  sub {
    my ($delay, $err_one, $one, $err_two, $two, $err_again, $again) = @_;
    $fail = $err_one || $err_two || $err_again;
    $result = [$one->hashes->first, $two->hashes->first, $again->hashes->first];
  }
)->wait;
ok !$fail, 'no error' or diag "err=$fail";
is_deeply $result, [{one => 1}, {two => 2}, {two => 2}], 'right structure';

# Connection cache
is $mysql->max_connections, 5, 'right default';
my @dbhs = map { $_->dbh } $mysql->db, $mysql->db, $mysql->db, $mysql->db, $mysql->db;
is_deeply \@dbhs, [map { $_->dbh } $mysql->db, $mysql->db, $mysql->db, $mysql->db, $mysql->db], 'same database handles';
@dbhs = ();
my $dbh = $mysql->max_connections(1)->db->dbh;
is $mysql->db->dbh, $dbh, 'same database handle';
isnt $mysql->db->dbh, $mysql->db->dbh, 'different database handles';
is $mysql->db->dbh, $dbh, 'different database handles';
$dbh = $mysql->db->dbh;
is $mysql->db->dbh, $dbh, 'same database handle';
$mysql->db->disconnect;
isnt $mysql->db->dbh, $dbh, 'different database handles';

# Fork safety
$dbh = $mysql->db->dbh;
{
  local $$ = -23;
  isnt $mysql->db->dbh, $dbh, 'different database handles';
};

# Blocking error
eval { $mysql->db->query('does_not_exist') };
like $@, qr/does_not_exist/, 'right error';

# Non-blocking error
($fail, $result) = ();
$mysql->db->query(
  'does_not_exist' => sub {
    my ($db, $err, $results) = @_;
    $fail   = $err;
    $result = $results;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
like $fail, qr/does_not_exist/, 'right error';
is $result->sth->errstr, $fail, 'same error';

done_testing();
