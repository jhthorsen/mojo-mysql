BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }
use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop;
use Mojo::Promise;
use Mojo::mysql;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
my $db    = $mysql->db;

ok $db->ping, 'connected';

$db->query(
  'create table if not exists crud_test (
     id   serial primary key,
     name text
   )'
);

note 'Create';
$db->insert('crud_test', {name => 'foo'});
is_deeply $db->select('crud_test')->hashes->to_array, [{id => 1, name => 'foo'}], 'right structure';
is $db->insert('crud_test', {name => 'bar'})->sth->{mysql_insertid}, 2, 'right value';
is_deeply $db->select('crud_test')->hashes->to_array, [{id => 1, name => 'foo'}, {id => 2, name => 'bar'}],
  'right structure';

note 'Read';
is_deeply $db->select('crud_test')->hashes->to_array, [{id => 1, name => 'foo'}, {id => 2, name => 'bar'}],
  'right structure';
is_deeply $db->select('crud_test', ['name'])->hashes->to_array, [{name => 'foo'}, {name => 'bar'}], 'right structure';
is_deeply $db->select('crud_test', ['name'], {name => 'foo'})->hashes->to_array, [{name => 'foo'}], 'right structure';
is_deeply $db->select('crud_test', ['name'], undef, {-desc => 'id'})->hashes->to_array,
  [{name => 'bar'}, {name => 'foo'}], 'right structure';

note 'Non-blocking read';
my $result;
my $delay = Mojo::IOLoop->delay(sub { $result = pop->hashes->to_array });
$db->select('crud_test', $delay->begin);
$delay->wait;
is_deeply $result, [{id => 1, name => 'foo'}, {id => 2, name => 'bar'}], 'right structure';
$result = undef;
$delay = Mojo::IOLoop->delay(sub { $result = pop->hashes->to_array });
$db->select('crud_test', undef, undef, {-desc => 'id'}, $delay->begin);
$delay->wait;
is_deeply $result, [{id => 2, name => 'bar'}, {id => 1, name => 'foo'}], 'right structure';

note 'Update';
$db->update('crud_test', {name => 'baz'}, {name => 'foo'});
is_deeply $db->select('crud_test', undef, undef, {-asc => 'id'})->hashes->to_array,
  [{id => 1, name => 'baz'}, {id => 2, name => 'bar'}], 'right structure';

note 'Delete';
$db->delete('crud_test', {name => 'baz'});
is_deeply $db->select('crud_test', undef, undef, {-asc => 'id'})->hashes->to_array, [{id => 2, name => 'bar'}],
  'right structure';
$db->delete('crud_test');
is_deeply $db->select('crud_test')->hashes->to_array, [], 'right structure';

note 'Promises';
$result = undef;
my $curid = undef;
$db->insert_p('crud_test', {name => 'promise'})->then(sub { $result = shift->last_insert_id })->wait;
is $result, 3, 'right result';
$curid  = $result;
$result = undef;
$db->select_p('crud_test', ['id', 'name'], {name => 'promise'})->then(sub { $result = shift->hash })->wait;
is_deeply $result, {name => 'promise', id => $curid}, 'right result';
$result = undef;
my $first  = $db->query_p("select * from crud_test where name = 'promise'");
my $second = $db->query_p("update crud_test set name = 'another_promise' where name = 'promise'");
my $third  = $db->select_p('crud_test', '*', {id => 3});
Mojo::Promise->all($first, $second, $third)->then(sub {
  my ($first, $second, $third) = @_;
  $result = [$first->[0]->hash, $second->[0]->affected_rows, $third->[0]->hash];
})->wait;
is $result->[0]{name}, 'promise', 'right result';
is $result->[1], 1, 'right result';
is $result->[2]{name}, 'another_promise', 'right result';
$result = undef;
$db->update_p('crud_test', {name => 'promise_two'}, {name => 'another_promise'},)
  ->then(sub { $result = shift->affected_rows })->wait;
is $result, 1, 'right result';
$db->delete_p('crud_test', {name => 'promise_two'})->then(sub { $result = shift->affected_rows })->wait;
is $result, 1, 'right result';

note 'Promises (rejected)';
my $fail;
$db->query_p('does_not_exist')->catch(sub { $fail = shift })->wait;
like $fail, qr/does_not_exist/, 'right error';

note 'cleanup';
END { $db and $db->query('drop table if exists crud_test'); }

done_testing;
