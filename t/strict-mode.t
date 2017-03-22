BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }
use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop;
use Mojo::mysql;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
ok $mysql->db->ping, 'connected';

my $db = $mysql->db;

$db->query('drop table if exists strict_mode_test_table');
$db->query('create table strict_mode_test_table (foo varchar(5))');

$db->query('SET SQL_MODE = ""');    # make sure this fails, even in mysql 5.7
$db->insert(strict_mode_test_table => {foo => 'too_long'});
is $db->select('strict_mode_test_table')->hash->{foo}, 'too_l', 'fetch invalid data';

is $mysql->strict_mode, $mysql, 'enabled strict mode';
eval { $mysql->db->insert(strict_mode_test_table => {foo => 'too_long'}) };
like $@, qr{Data too long.*foo}, 'too long string';

is $mysql->strict_mode(0), $mysql, 'disable strict mode';

$mysql = Mojo::mysql->strict_mode($ENV{TEST_ONLINE});
isa_ok($mysql, 'Mojo::mysql');
eval { $mysql->db->insert(strict_mode_test_table => {foo => 'too_long'}) };
like $@, qr{Data too long.*foo}, 'constructed Mojo::mysql from strict_mode()';

$db->query('drop table if exists strict_mode_test_table');

done_testing;
