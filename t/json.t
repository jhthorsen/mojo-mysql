use Mojo::Base -strict;
use Mojo::mysql;
use Test::More;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
my $db    = $mysql->db;

eval {
  $db->query('create table if not exists mojo_json_test (id int(10), name varchar(60), j json)');
  $db->query('truncate table mojo_json_test');
  $db->query('insert into mojo_json_test (id, name, j) values (?, ?, ?)', $$, $0, {json => {foo => 42}});
} or do {
  plan skip_all => $@;
};

is $db->query('select json_type(j) from mojo_json_test')->array->[0],             'OBJECT', 'json_type';
is $db->query('select json_extract(j, "$.foo") from mojo_json_test')->array->[0], '42',     'json_extract';
is_deeply $db->query('select id, name, j from mojo_json_test where json_extract(j, "$.foo") = 42')->expand->hash,
  {id => $$, name => $0, j => {foo => 42}}, 'expand json';

my $value_hash = {nick => 'supergirl'};
my $value_json = Mojo::JSON::to_json($value_hash);
my $query      = 'select name from mojo_json_test where name like "%supergirl%"';
$db->query('insert into mojo_json_test (name) values (?)', {json => {nick => 'supergirl'}});

is_deeply $db->query($query)->expand->hash, {name => $value_json}, 'hash: name as string';

is_deeply $db->query($query)->expand(1)->hash, {name => $value_hash}, 'hash: name as hash';

is_deeply $db->query($query)->expand->hashes, [{name => $value_json}], 'hashes: name as string';

is_deeply $db->query($query)->expand(1)->hashes, [{name => $value_hash}], 'hashes: name as hash';

is_deeply $db->query($query)->expand->array, [$value_json], 'array: name as string';

is_deeply $db->query($query)->expand(1)->array, [$value_hash], 'array: name as hash';

is_deeply $db->query($query)->expand->arrays, [[$value_json]], 'arrays: name as string';

is_deeply $db->query($query)->expand(1)->arrays, [[$value_hash]], 'arrays: name as hash';

$db->query('drop table mojo_json_test') unless $ENV{TEST_KEEP_DB};

done_testing;
