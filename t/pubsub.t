BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }
use Mojo::Base -strict;
use Mojo::IOLoop;
use Mojo::mysql;
use Test::More;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
my (@pids, @test, $first, $second);
$mysql->pubsub->on(reconnect => sub { push @pids, pop->pid });
$first = $mysql->pubsub->listen(test => sub { push @test, pop });
Mojo::IOLoop->delay(
  sub {
    Mojo::IOLoop->timer(0.05, shift->begin);
    $mysql->pubsub->notify(test => 'first');
  },
  sub {
    Mojo::IOLoop->timer(0.05, shift->begin);
    is_deeply \@test, ['first'], 'right messages 1';
    $mysql->db->query('insert into mojo_pubsub_notify(channel, payload) values (?, ?)', 'test', 'second');
  },
  sub {
    Mojo::IOLoop->timer(0.05, shift->begin);
    is_deeply \@test, ['first', 'second'], 'right messages 1-2';
    $mysql->db->query('insert into mojo_pubsub_notify(channel, payload) values (?, ?), (?, ?), (?, ?)',
      'test', 'third', 'test', 'fourth', 'test', 'fifth');
  },
  sub {
    Mojo::IOLoop->timer(0.05, shift->begin);
    is_deeply \@test, ['first', 'second', 'third', 'fourth', 'fifth'], 'right messages 1-5';
    @test = ();

    # Second subscribe
    $second = $mysql->pubsub->listen(test => sub { push @test, pop });
    $mysql->pubsub->notify('test')->notify(test => 'first');
  },
  sub {
    Mojo::IOLoop->timer(0.05, shift->begin);
    is_deeply \@test, ['', '', 'first', 'first'], 'right messages dual';
    $mysql->pubsub->unlisten(test => $first)->notify(test => 'second');
  },
  sub {
    Mojo::IOLoop->timer(0.05, shift->begin);
    is_deeply \@test, ['', '', 'first', 'first', 'second'], 'right messages single';

    @test = ();
    $mysql->pubsub->{db}->{dbh}->{Warn} = 0;
    $mysql->db->query('kill ?', $pids[0]);
    $mysql->pubsub->notify(test => 'works');
  },
  sub {
    ok $pids[1], 'second database pid';
    isnt $pids[0], $pids[1], 'different database pids';
    is_deeply \@test, ['works'], 'right message after reconnect';
  }
)->wait;

$mysql->migrations->name('pubsub')->from_data('Mojo::mysql::PubSub')->migrate(0);

done_testing();
