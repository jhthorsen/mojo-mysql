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
Mojo::IOLoop->delay(
  sub {
    Mojo::IOLoop->timer(0.05, shift->begin);
    $mysql->pubsub->notify('pstest')->notify(pstest => 'first');
  },
  sub {
    Mojo::IOLoop->timer(0.05, shift->begin);
    is_deeply \@test, ['', '', 'first', 'first'], 'right messages';
    $mysql->pubsub->unlisten(pstest => $first)->notify(pstest => 'second');
  },
  sub {
    Mojo::IOLoop->timer(0.05, shift->begin);
    is_deeply \@test, ['', '', 'first', 'first', 'second'], 'right messages';
    $mysql->pubsub->unlisten(pstest => $second)->notify(pstest => 'third');
  },
  sub {
    is_deeply \@test, ['', '', 'first', 'first', 'second'], 'right messages';
  }
)->wait;

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
  Mojo::IOLoop->delay(
    sub { Mojo::IOLoop->timer(0.05, shift->begin); },
    sub { is_deeply \@test, ['works'], 'right messages'; }
  )->wait;
};

$mysql->migrations->name('pubsub')->from_data('Mojo::mysql::PubSub')->migrate(0);

done_testing();
