use Mojo::Base -strict;
use Test::More;
use Mojo::mysql;

plan skip_all => 'TEST_ONLINE=mariadb://root@/test' unless $ENV{TEST_ONLINE} and $ENV{TEST_ONLINE} =~ m!^mariadb:!;

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});

ok $mysql->db->ping, 'connected';
is $mysql->db->dbh->{Driver}{Name}, 'MariaDB', 'driver name';

done_testing;
