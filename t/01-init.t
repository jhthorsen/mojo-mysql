use Mojo::Base -strict;
use Mojo::mysql;
use Test::More;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
my $db;

eval { $db = $mysql->db; };
if ($@) {
  die $@ unless $@ =~ /Authentication requires secure connection/;

  # assume we are on MySQL 8 and try again with SSL
  $mysql = Mojo::mysql->new("$ENV{TEST_ONLINE};mysql_ssl=1");
  ok $db = $mysql->db, 'SSL connection established';
}
else {
  pass 'connection established';
}

done_testing;
