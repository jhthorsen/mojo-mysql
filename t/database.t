BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }
use Mojo::Base -strict;
use Test::More;
use DBI ':sql_types';
use Mojo::IOLoop;
use Mojo::mysql;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
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
is_deeply $result, [{one => 1}, {two => 2}, {two => 2}], 'concurrent non-blocking selects';

# Sequential and Concurrent non-blocking selects
($fail, $result) = ();
Mojo::IOLoop->delay(
  sub {
    my $delay = shift;
    $db->query('select 1 as one' => $delay->begin);
  },
  sub {
    my ($delay, $err, $res) = @_;
    $fail   = $err;
    $result = [$res->hashes->first];
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
my @pids = sort map { $_->pid } $mysql->db, $mysql->db, $mysql->db, $mysql->db, $mysql->db;
is_deeply \@pids, [sort map { $_->pid } $mysql->db, $mysql->db, $mysql->db, $mysql->db, $mysql->db],
  'same database pids';
my $pid = $mysql->max_connections(1)->db->pid;
is $mysql->db->pid, $pid, 'same database pid';
isnt $mysql->db->pid, $mysql->db->pid, 'different database pids';
is $mysql->db->pid, $pid, 'different database pid';
$pid = $mysql->db->pid;
is $mysql->db->pid, $pid, 'same database pid';
$mysql->db->disconnect;
isnt $mysql->db->pid, $pid, 'different database pid';

# Binary data
$db = $mysql->db;
my $bytes = "\xF0\xF1\xF2\xF3";
is_deeply $db->query('select binary ? as foo',
  {type => SQL_BLOB, value => $bytes})->hash, {foo => $bytes}, 'right data';

# Fork safety
$pid = $mysql->db->pid;
{
  local $$ = -23;
  isnt $mysql->db->pid, $pid, 'different database handles';
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

# Clean up non-blocking queries
($fail, $result) = ();
$db = $mysql->db;
$db->query(
  'select 1' => sub {
    my ($db, $err, $results) = @_;
    ($fail, $result) = ($err, $results);
  }
);
$db->disconnect;
undef $db;
is $fail, 'Premature connection close', 'right error';

# Error context
my ($err, $res);
eval { $mysql->db->query('select * from table_does_not_exist') };
like $@, qr/database\.t line/, 'error context blocking';
$mysql->db->query(
  'select * from table_does_not_exist',
  sub {
    (my $db, $err, $res) = @_;
    Mojo::IOLoop->stop;
  }
);

Mojo::IOLoop->start;
like $err, qr/database\.t line/, 'error context non-blocking';

done_testing();
