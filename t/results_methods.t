use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test'
  unless $ENV{TEST_ONLINE};

use Mojo::IOLoop;
use Mojo::mysql;

my $mysql = Mojo::mysql->new($ENV{TEST_ONLINE});
$mysql->url->options->{found_rows} = 0;
my $db = $mysql->db;
$db->query(
  'create table if not exists results_test (
     id   integer auto_increment primary key,
     name text
   )'
);
$db->query('truncate table results_test');

my $res = $db->query('insert into results_test (name) values (?)', 'foo');
is $res->affected_rows, 1, 'right affected_rows';
is $res->last_insert_id, 1, 'right last_insert_id';
is $res->warnings_count, 0, 'no warnings';
is $res->err, undef, 'no error';
is $res->errstr, undef, 'no error';
is $res->state, '', 'no state';


$res = $db->query('insert into results_test (name) values (?)', 'bar');
is $res->affected_rows, 1, 'right affected_rows';
is $res->last_insert_id, 2, 'right last_insert_id';
is $res->warnings_count, 0, 'no warnings';


is $db->query('update results_test set name=? where name=?', 'foo', 'foo1')->affected_rows, 0, 'right affected rows';
is $db->query('update results_test set name=? where name=?', 'foo', 'foo')->affected_rows, 0, 'right affected rows';
is $db->query('update results_test set id=1 where id=1')->affected_rows, 0, 'right affected rows';

my $count = $db->{dbh} && $db->dbh->{mysql_use_result} ? 0 : 1;
$res = $db->query("select 1 + '4a'");
is_deeply $res->arrays, [[5 ]];
is $res->warnings_count, $count, 'warnings';

$res = $db->query('show warnings');
like $res->hashes->[0]->{Message}, qr/Truncated/, 'warning message';

$db->disconnect;

$mysql->url->options->{found_rows} = 1;
$db = $mysql->db;

is $db->query('update results_test set name=? where name=?', 'foo', 'foo1')->affected_rows, 0, 'right affected rows';
is $db->query('update results_test set name=? where name=?', 'foo', 'foo')->affected_rows, 1, 'right affected rows';
is $db->query('update results_test set id=1 where id=1')->affected_rows, 1, 'right affected rows';

$db->query('drop table results_test');

my $err;
Mojo::IOLoop->delay(
	sub {
		my $delay = shift;
		$db->query('select name from results_test', $delay->begin);
	},
	sub {
		my $delay = shift;
		$err = shift;
		$res = shift;
	}
)->wait;
like $err, qr/results_test/, 'has error';
is $err, $res->errstr, 'same error';
is length($res->state), 5, 'has state';

done_testing;
