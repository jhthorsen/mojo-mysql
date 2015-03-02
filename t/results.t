use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Mojo::mysql;

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
my $db    = $mysql->db->do(
  'create table if not exists results_test (
     id serial primary key,
     name varchar(255)
   )'
);
$db->do('truncate table results_test');
$db->query('insert into results_test (name) values (?)', $_) for qw(foo bar);

# Result methods
is_deeply $db->query('select * from results_test')->rows, 2, 'two rows';
is_deeply $db->query('select * from results_test')->columns, ['id', 'name'], 'right structure';
is_deeply $db->query('select * from results_test')->array,   [1,    'foo'],  'right structure';
is_deeply [$db->query('select * from results_test')->arrays->each], [[1, 'foo'], [2, 'bar']], 'right structure';
is_deeply $db->query('select * from results_test')->hash, {id => 1, name => 'foo'}, 'right structure';
is_deeply [$db->query('select * from results_test')->hashes->each],
  [{id => 1, name => 'foo'}, {id => 2, name => 'bar'}], 'right structure';
is $mysql->db->query('select * from results_test')->text, "1  foo\n2  bar\n", 'right text';

# Transactions
{
  my $tx = $db->begin;
  $db->do("insert into results_test (name) values ('tx1')")->do("insert into results_test (name) values ('tx1')");
  $tx->commit;
}

{
  my $tx = $db->begin;
  $db->do("insert into results_test (name) values ('tx2')")->do("insert into results_test (name) values ('tx2')")
}

is_deeply [$db->query('select * from results_test where name = ?', 'tx1')->hashes->each],
  [{id => 3, name => 'tx1'}, {id => 4, name => 'tx1'}], 'right structure';
is_deeply [$db->query('select * from results_test where name = ?', 'tx2')->hashes->each], [], 'no results';

$db->do('drop table results_test');

done_testing();
