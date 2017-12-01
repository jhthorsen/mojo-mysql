BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }
use Mojo::Base -strict;
use Test::More;
use Mojo::IOLoop;
use Mojo::mysql;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $pg = Mojo::mysql->new($ENV{TEST_ONLINE});
my $db = $pg->db;

ok $db->ping, 'connected';

$db->query(
  'create table if not exists crud_test (
     id   serial primary key,
     name text
   )'
);

# Create
$db->insert('crud_test', {name => 'foo'});
is_deeply $db->select('crud_test')->hashes->to_array, [{id => 1, name => 'foo'}], 'right structure';
is $db->insert('crud_test', {name => 'bar'})->sth->{mysql_insertid}, 2, 'right value';
is_deeply $db->select('crud_test')->hashes->to_array, [{id => 1, name => 'foo'}, {id => 2, name => 'bar'}],
  'right structure';

# Read
is_deeply $db->select('crud_test')->hashes->to_array, [{id => 1, name => 'foo'}, {id => 2, name => 'bar'}],
  'right structure';
is_deeply $db->select('crud_test', ['name'])->hashes->to_array, [{name => 'foo'}, {name => 'bar'}], 'right structure';
is_deeply $db->select('crud_test', ['name'], {name => 'foo'})->hashes->to_array, [{name => 'foo'}], 'right structure';
is_deeply $db->select('crud_test', ['name'], undef, {-desc => 'id'})->hashes->to_array,
  [{name => 'bar'}, {name => 'foo'}], 'right structure';

# Non-blocking read
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

# Update
$db->update('crud_test', {name => 'baz'}, {name => 'foo'});
is_deeply $db->select('crud_test', undef, undef, {-asc => 'id'})->hashes->to_array,
  [{id => 1, name => 'baz'}, {id => 2, name => 'bar'}], 'right structure';

# Delete
$db->delete('crud_test', {name => 'baz'});
is_deeply $db->select('crud_test', undef, undef, {-asc => 'id'})->hashes->to_array, [{id => 2, name => 'bar'}],
  'right structure';
$db->delete('crud_test');
is_deeply $db->select('crud_test')->hashes->to_array, [], 'right structure';

# cleanup
END { $db and $db->query('drop table if exists crud_test'); }

done_testing();
