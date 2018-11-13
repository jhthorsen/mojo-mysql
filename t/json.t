use Mojo::Base -strict;
use Mojo::mysql;
use Test::More;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
my $db    = $mysql->db;

eval {
  $db->query('create table if not exists mojo_json_test (id int(10), name varchar(60), j json)');
  $db->query('insert into mojo_json_test (id, name, j) values (?, ?, ?)', $$, $0, {json => {foo => 42}});
} or do {
  plan skip_all => $@;
};

is $db->query('select json_type(j) from mojo_json_test')->array->[0],             'OBJECT', 'json_type';
is $db->query('select json_extract(j, "$.foo") from mojo_json_test')->array->[0], '42',     'json_extract';
is_deeply $db->query('select id, name, j from mojo_json_test where json_extract(j, "$.foo") = 42')->expand->hash,
  {id => $$, name => $0, j => {foo => 42}}, 'expand json';

$db->query('insert into mojo_json_test (name) values (?)', {json => {nick => 'supergirl'}});
is_deeply $db->query('select name from mojo_json_test where name like "%supergirl%"')->expand->hash,
  {name => Mojo::JSON::to_json({nick => 'supergirl'})}, 'name as string';

is_deeply $db->query('select name from mojo_json_test where name like "%supergirl%"')->expand(1)->hash,
  {name => {nick => 'supergirl'}}, 'name as hash';

$db->query('drop table mojo_json_test');

done_testing;
