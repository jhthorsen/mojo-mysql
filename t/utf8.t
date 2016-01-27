BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }
use Mojo::Base -strict;
use Mojo::mysql;
use Test::More;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
my $db    = $mysql->db;
$db->query(
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

$db->query('drop table results_test');

done_testing();
