BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }
use Mojo::Base -strict;
use Mojo::mysql;
use Test::More;

plan skip_all => 'TEST_PUBSUB=1 TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_PUBSUB} && $ENV{TEST_ONLINE};

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
my (@pids, @payload);

{
  my @warn;
  local $SIG{__WARN__} = sub { push @warn, $_[0] };
  $mysql->pubsub->on(reconnect => sub { push @pids, pop->pid });
  like "@warn", qr{EXPERIMENTAL}, 'pubsub() will warn';
}

$ENV{MOJO_PUBSUB_EXPERIMENTAL} = 1;

$mysql->pubsub->notify(test => 'skipped_message');
my $sa = $mysql->pubsub->listen(test => sub { push @payload, a => pop });
$mysql->pubsub->notify(test => 'm1');
wait_for(1 => 'one subscriber');
is_deeply \@payload, [a => 'm1'], 'right message m1';

$mysql->db->query('insert into mojo_pubsub_notify (channel, payload) values (?, ?)', 'test', 'm2');
wait_for(1 => 'one subscriber');
is_deeply \@payload, [a => 'm2'], 'right message m2';

$mysql->db->query('insert into mojo_pubsub_notify (channel, payload) values (?, ?), (?, ?), (?, ?), (?, ?)',
  'test', 'm3', 'test', 'm4', 'skipped_channel', 'x1', 'test', 'm5');
wait_for(3 => 'skipped channel');
is_deeply \@payload, [map { (a => "m$_") } 3 .. 5], 'right messages 3..5';

my $sb = $mysql->pubsub->listen(test => sub { push @payload, b => pop });
$mysql->pubsub->notify(test => undef)->notify(test => 'd2');
wait_for(4, 'two subscribers');
is_deeply \@payload, [map { (a => $_, b => $_) } ('', 'd2')], 'right messages undef + d2';

$mysql->pubsub->unlisten(test => $sa)->notify(test => 'u1');
wait_for(1 => 'unlisten');
is_deeply \@payload, [b => 'u1'], 'right message after unlisten';

$mysql->pubsub->{db}{dbh}{Warn} = 0;
$mysql->db->query('kill ?', $pids[0]);
$mysql->pubsub->notify(test => 'k1');
wait_for(1 => 'reconnect');
isnt $pids[0], $pids[1], 'different database pids';
is_deeply \@payload, [b => 'k1'], 'right message after reconnect';

$mysql->migrations->name('pubsub')->from_data('Mojo::mysql::PubSub')->migrate(0);

done_testing;

sub wait_for {
  my ($n, $descr) = @_;
  note "[$n] $descr";
  @payload = ();
  my $tid = Mojo::IOLoop->recurring(0.05 => sub { @payload == $n * 2 and Mojo::IOLoop->stop });
  Mojo::IOLoop->start;
  Mojo::IOLoop->remove($tid);
}
