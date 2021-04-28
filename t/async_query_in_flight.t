use Mojo::Base -strict;
use Mojo::mysql;
use Test::More;

plan skip_all => 'TEST_FOR=500 TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_FOR} and $ENV{TEST_ONLINE};

my $mysql     = Mojo::mysql->new($ENV{TEST_ONLINE})->max_connections(int($ENV{TEST_FOR} / 3));
my $in_flight = 0;
my $n         = $ENV{TEST_FOR};
my @err;

my $cb = sub {
  my ($db, $err, $res) = @_;
  push @err, $err if $err;
  Mojo::IOLoop->stop unless --$in_flight;
};

Mojo::IOLoop->recurring(
  0.01,
  sub {
    return unless $n-- > 0;
    $in_flight += 2;
    $mysql->db->query("SELECT NOW()",      $cb);
    $mysql->db->query("SELECT SLEEP(0.1)", $cb);
  },
);

Mojo::IOLoop->start;
is_deeply \@err, [], 'gathering async_query_in_flight results for the wrong handle was not seen';

done_testing;
