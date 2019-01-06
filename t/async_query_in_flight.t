use Mojo::Base -strict;
use Test::More;
use Mojo::mysql;

plan skip_all => 'TEST_FOR=500 TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_FOR} and $ENV{TEST_ONLINE};

my $mysql     = Mojo::mysql->new($ENV{TEST_ONLINE})->max_connections(int($ENV{TEST_FOR} / 3));
my $in_flight = 0;
my $n         = $ENV{TEST_FOR};
my $order     = '';
my @err;

Mojo::IOLoop->recurring(
  0.01,
  sub {
    return unless $n-- > 0;
    Mojo::IOLoop->delay(
      sub {
        my ($delay) = @_;
        $order .= 'q';
        $in_flight++;
        $mysql->db->query("SELECT NOW()",      $delay->begin);
        $mysql->db->query("SELECT SLEEP(0.1)", $delay->begin);
      },
      sub {
        my ($delay, $err, $res, $err2, $res2) = @_;

        eval {
          push @err, $err if $err ||= $err2;
          $order .= 'r' if $res->array->[0];
          1;
        } or do {
          push @err, $@;
        };

        Mojo::IOLoop->stop unless --$in_flight;
      }
    )->catch(sub { push @err, pop; Mojo::IOLoop->stop; });
  }
);

$order = 's';
Mojo::IOLoop->start;

is_deeply \@err, [], 'Gathering async_query_in_flight results for the wrong handle was not seen';
is @err, 0, 'errors';
like $order, qr{}, 'order is correct';

$n = $ENV{TEST_FOR} * 2;
like $order, qr/^s\w{$n}$/, "got 1+$n" or diag "len=" . length $order;

done_testing;
