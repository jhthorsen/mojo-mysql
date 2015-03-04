use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test' unless $ENV{TEST_ONLINE};

use Mojo::mysql;

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
my $db    = $mysql->db->do(
  'create table if not exists results_test (
     id serial primary key,
     name varchar(255) charset utf8
   )'
);
$db->query('truncate table results_test');
$db->query('insert into results_test (name) values (?)', $_) for qw(☺ ☻);

# Result methods
is_deeply $db->query('select * from results_test')->rows, 2, 'two rows';
is_deeply $db->query('select * from results_test')->columns, ['id', 'name'], 'right structure';
is_deeply $db->query('select * from results_test')->array,   [1,    '☺'],  'right structure';
is_deeply [$db->query('select * from results_test')->arrays->each], [[1, '☺'], [2, '☻']], 'right structure';
is_deeply $db->query('select * from results_test')->hash, {id => 1, name => '☺'}, 'right structure';
is_deeply [$db->query('select * from results_test')->hashes->each],
  [{id => 1, name => '☺'}, {id => 2, name => '☻'}], 'right structure';
is $mysql->db->query('select * from results_test')->text, "1  ☺\n2  ☻\n", 'right text';

$db->do('drop table results_test');

done_testing();
