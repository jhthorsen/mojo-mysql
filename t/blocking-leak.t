use Mojo::Base -strict;
use Mojo::mysql;
use Test::More;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $n_times = $ENV{N_TIMES} || 10;
my $mysql   = Mojo::mysql->new($ENV{TEST_ONLINE});
my $db      = $mysql->db;

$db->query('create table if not exists test_mojo_mysql_blocking_leak (id serial primary key, name text)');
$db->query('insert into test_mojo_mysql_blocking_leak (name) values (?)', $_) for $0, $$;

note '$db->query(...)';
for (1 .. $n_times) {
  $db->query('select name from test_mojo_mysql_blocking_leak')->hash;
}

is $db->backlog, 0, 'zero since blocking';
is @{$db->{done_sth}}, 0, 'done_sth';

note '$mysql->db->query(...)';
for (1 .. $n_times) {
  $mysql->db->query('select name from test_mojo_mysql_blocking_leak')->hash;
}

is @{$db->{done_sth}}, 0, 'done_sth';

$db->query('drop table test_mojo_mysql_blocking_leak');

done_testing;
