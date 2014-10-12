use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Mojo::IOLoop;
use Mojo::mysql;

$ENV{MOD_PERL} = 1;

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
ok $mysql->db->ping, 'connected';
is $mysql->db->dbh->{mysql_auto_reconnect}, 0, 'mysql_auto_reconnect=0';

done_testing;
