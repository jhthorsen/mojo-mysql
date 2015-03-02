use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Mojo::IOLoop;
use Mojo::mysql;

# Defaults
my $mysql = Mojo::mysql->new;
is $mysql->database, '',                      'right database';
is $mysql->username, '',                      'no username';
is $mysql->password, '',                      'no password';
is_deeply $mysql->options, {multi_statements => 0, multi_results => 1,
  utf8 => 1, found_rows => 0,
  connect_timeout => 10, query_timeout => 30}, 'right options';

# Minimal connection string
$mysql = Mojo::mysql->new('mysql:///test1');
is $mysql->database, 'test1',                  'right database';
is $mysql->username, '',                       'no username';
is $mysql->password, '',                       'no password';
is_deeply $mysql->options, {multi_statements => 0, multi_results => 1,
  utf8 => 1, found_rows => 0,
  connect_timeout => 10, query_timeout => 30}, 'right options';

# Connection string with host and port
$mysql = Mojo::mysql->new('mysql://127.0.0.1:8080/test2');
is $mysql->host, '127.0.0.1', 'right host';
is $mysql->port, 8080, 'right port';
is $mysql->database, 'test2', 'right database';
is $mysql->username, '',                                                'no username';
is $mysql->password, '',                                                'no password';
is_deeply $mysql->options, {multi_statements => 0, multi_results => 1,
  utf8 => 1, found_rows => 0,
  connect_timeout => 10, query_timeout => 30}, 'right options';

# Connection string username but without host
$mysql = Mojo::mysql->new('mysql://root@/test3');
is $mysql->host, 'localhost', 'right host';
is $mysql->port, 3306, 'right port';
is $mysql->database, 'test3', 'right database';
is $mysql->username, 'root',                   'right username';
is $mysql->password, '',                       'no password';
is_deeply $mysql->options, {multi_statements => 0, multi_results => 1,
  utf8 => 1, found_rows => 0,
  connect_timeout => 10, query_timeout => 30}, 'right options';

# Connection string with unix domain socket and options
#$mysql = Mojo::mysql->new('mysql://x1:y2@%2ftmp%2fmysql.sock/test4?PrintError=1&RaiseError=0');
#is $mysql->dsn,      'dbi:mysql:dbname=test4;host=/tmp/mysql.sock', 'right data source';
#is $mysql->username, 'x1',                                          'right username';
#is $mysql->password, 'y2',                                          'right password';
#is_deeply $mysql->options, {multi_statements => 0, multi_results => 1,
#  utf8 => 1, found_rows => 0,
#  connect_timeout => 10, query_timeout => 30}, 'right options';

# Connection string with lots of zeros
$mysql = Mojo::mysql->new('mysql://0:0@/0?multi_results=0');
is $mysql->host, 'localhost', 'right host';
is $mysql->port, 3306, 'right port';
is $mysql->username, '0',                  'right username';
is $mysql->password, '0',                  'right password';
is_deeply $mysql->options, {multi_statements => 0, multi_results => 0,
  utf8 => 1, found_rows => 0,
  connect_timeout => 10, query_timeout => 30}, 'right options';

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

# Sequential and Concurrent non-blocking selects
($fail, $result) = ();
Mojo::IOLoop->delay(
  sub {
    my $delay = shift;
    $db->query('select 1 as one' => $delay->begin);
  },
  sub {
    my ($delay, $err, $res) = @_;
    $fail = $err;
    $result = [ $res->hashes->first ];
    $db->query('select 2 as two' => $delay->begin);
    $db->query('select 2 as two' => $delay->begin);
  },
  sub {
    my ($delay, $err_two, $two, $err_again, $again) = @_;
    push @$result, $db->query('select 1 as one')->hashes->first;
    $fail ||= $err_two || $err_again;
    push @$result, $two->hashes->first, $again->hashes->first;
    $db->query('select 3 as three' => $delay->begin);
  },
  sub {
    my ($delay, $err_three, $three) = @_;
    $fail ||= $err_three;
    push @$result, $three->hashes->first;
  }
)->wait;
ok !$fail, 'no error' or diag "err=$fail";
is_deeply $result, [{one => 1}, {one => 1}, {two => 2}, {two => 2}, {three => 3}], 'right structure';

# Connection cache
is $mysql->max_connections, 5, 'right default';
my @pids = map { $_->pid } $mysql->db, $mysql->db, $mysql->db, $mysql->db, $mysql->db;
my @again = map { $_->pid } $mysql->db, $mysql->db, $mysql->db, $mysql->db, $mysql->db;
is_deeply \@pids, [map { $_->pid } $mysql->db, $mysql->db, $mysql->db, $mysql->db, $mysql->db], 'same database handles';
@pids = ();
my $connection = $mysql->max_connections(1)->db->connection;
is $mysql->db->connection, $connection, 'same database handle';
isnt $mysql->db->connection, $mysql->db->connection, 'different database handles';
is $mysql->db->connection, $connection, 'different database handles';
$connection = $mysql->db->connection;
is $mysql->db->connection, $connection, 'same database handle';
$mysql->db->disconnect;
isnt $mysql->db->connection, $connection, 'different database handles';

# Fork safety
$connection = $mysql->db->connection;
{
  local $$ = -23;
  isnt $mysql->db->connection, $connection, 'different database handles';
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
#is $result->sth->errstr, $fail, 'same error';

done_testing();
