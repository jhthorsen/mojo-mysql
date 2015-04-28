use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test'
  unless $ENV{TEST_ONLINE};

use Mojo::IOLoop;
use Mojo::mysql;

# Notifications with event loop
my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
my ($db, @test);
$mysql->pubsub->on(reconnect => sub { $db = pop });
$mysql->pubsub->listen(
  pstest => sub {
    my ($pubsub, $payload) = @_;
    push @test, $payload;
    Mojo::IOLoop->next_tick(sub { $pubsub->notify(pstest => 'stop') });
    Mojo::IOLoop->stop if $payload eq 'stop';
  }
);
$mysql->pubsub->notify(pstest => 'test');
Mojo::IOLoop->start;
is_deeply \@test, ['test', 'stop'], 'right messages';

# Unsubscribe
$mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
$db = undef;
$mysql->pubsub->on(reconnect => sub { $db = pop });
@test = ();
my $first  = $mysql->pubsub->listen(pstest => sub { push @test, pop });
my $second = $mysql->pubsub->listen(pstest => sub { push @test, pop });
$mysql->pubsub->notify('pstest')->notify(pstest => 'first');
is_deeply \@test, ['', '', 'first', 'first'], 'right messages';
$mysql->pubsub->unlisten(pstest => $first)->notify(pstest => 'second');
is_deeply \@test, ['', '', 'first', 'first', 'second'], 'right messages';
$mysql->pubsub->unlisten(pstest => $second)->notify(pstest => 'third');
is_deeply \@test, ['', '', 'first', 'first', 'second'], 'right messages';

# Reconnect while listening
$mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
my @dbhs = @test = ();
$mysql->pubsub->on(reconnect => sub { push @dbhs, pop->dbh });
$mysql->pubsub->listen(pstest => sub { push @test, pop });
ok $dbhs[0], 'database handle';
is_deeply \@test, [], 'no messages';
{
  local $dbhs[0]{Warn} = 0;
  $mysql->pubsub->on(
    reconnect => sub { shift->notify(pstest => 'works'); Mojo::IOLoop->stop });
  $mysql->db->query('kill ?', $dbhs[0]{mysql_thread_id});
  Mojo::IOLoop->start;
  ok $dbhs[1], 'database handle';
  isnt $dbhs[0], $dbhs[1], 'different database handles';
  is_deeply \@test, ['works'], 'right messages';
};

# Reconnect while not listening
$mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
@dbhs = @test = ();
$mysql->pubsub->on(reconnect => sub { push @dbhs, pop->dbh });
$mysql->pubsub->notify(pstest => 'fail');
ok $dbhs[0], 'database handle';
is_deeply \@test, [], 'no messages';
{
  local $dbhs[0]{Warn} = 0;
  $mysql->pubsub->on(reconnect => sub { Mojo::IOLoop->stop });
  $mysql->db->query('kill ?', $dbhs[0]{mysql_thread_id});
  Mojo::IOLoop->start;
  ok $dbhs[1], 'database handle';
  isnt $dbhs[0], $dbhs[1], 'different database handles';
  $mysql->pubsub->listen(pstest => sub { push @test, pop });
  $mysql->pubsub->notify(pstest => 'works too');
  is_deeply \@test, ['works too'], 'right messages';
};

# Fork-safety
$mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
@dbhs = @test = ();
$mysql->pubsub->on(reconnect => sub { push @dbhs, pop->dbh });
$mysql->pubsub->listen(pstest => sub { push @test, pop });
ok $dbhs[0], 'database handle';
ok $dbhs[0]->ping, 'connected';
$mysql->pubsub->notify(pstest => 'first');
is_deeply \@test, ['first'], 'right messages';
{
  local $$ = -23;
  $mysql->pubsub->notify(pstest => 'second');
  ok $dbhs[1], 'database handle';
  ok $dbhs[1]->ping, 'connected';
  isnt $dbhs[0], $dbhs[1], 'different database handles';
  ok !$dbhs[0]->ping, 'not connected';
  is_deeply \@test, ['first'], 'right messages';
  $mysql->pubsub->listen(pstest => sub { push @test, pop });
  $mysql->pubsub->notify(pstest => 'third');
  ok $dbhs[1]->ping, 'connected';
  ok !$dbhs[2], 'no database handle';
  is_deeply \@test, ['first', 'third'], 'right messages';
};

done_testing();
