use Test::More;
use Mojo::Base -strict;
use File::Temp ();
use Mojo::IOLoop;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $stderr = File::Temp->new;

die $! unless defined(my $pid = fork);
unless ($pid) {
  open STDERR, '>&', fileno($stderr) or die $!;
  require Mojo::mysql;
  my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
  Mojo::Promise->all(Mojo::Promise->timeout(0.2), $mysql->db->query_p('select sleep(1)'))->wait;
  exit;
}

wait;
$stderr->seek(0, 0);
$stderr = join '', <$stderr>;
$stderr =~ s/^\s*//g;
like $stderr, qr{^Unhandled rejected}s,
  q(Avoid: Can't call method "next_tick" on an undefined value at Mojo/Promise.pm);

done_testing;
