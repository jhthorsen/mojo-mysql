use Mojo::Base -strict;
use Mojo::mysql;
use Test::More;

plan skip_all => 'TEST_ONLINE=mysql://root@/test' unless $ENV{TEST_ONLINE};

my $mysql  = Mojo::mysql->new($ENV{TEST_ONLINE});
my $db     = $mysql->db;
my $dbname = 'mojo_mysql1';

note 'Create table';
$db->query(<<EOF);
create table if not exists mojo_mysql1 (
  id int not null,
  f1 varchar(20),
  f2 varchar(20),
  f3 varchar(20),
  primary key (id)
);
EOF
$db->query('truncate table mojo_mysql1');

note 'Insert values';
my @testdata = (
  {id => 1, f1 => 'one first',  f2 => 'two first',  f3 => 'three first'},
  {id => 2, f1 => 'one second', f2 => 'two second', f3 => 'three second'},
  {id => 3, f1 => 'one third',  f2 => 'two third',  f3 => 'three third'},
);

for my $data (@testdata) {
  is $db->insert($dbname, $data)->rows, 1, 'insert values';
}

is $db->select($dbname)->rows, scalar(@testdata), 'size of db';

note 'On conflict';
my $conflict = {id => 1, f1 => 'one conflict'};

eval { $db->insert($dbname, $conflict); };
like $@, qr/Duplicate entry/, 'unable to insert conflict';

is $db->insert($dbname, $conflict, {on_conflict => 'ignore'})->rows, 0, 'ignore conflict';

is $db->insert($dbname, $conflict, {on_conflict => 'replace'})->rows, 2, 'replace';
is $db->select($dbname)->rows, scalar(@testdata), 'size of db';
is $db->select($dbname, 'f1', {id => 1})->hash->{f1}, 'one conflict', 'value replaced';

$conflict->{f1} = 'another conflict';
my $msg = 'we had a conflict';
is $db->insert($dbname, $conflict, {on_conflict => {f3 => $msg}})->rows, 2, 'update';
is_deeply $db->select($dbname, ['f1', 'f3'])->hash, {f1 => 'one conflict', f3 => $msg}, 'value updated';

note 'Cleanup';
$db->query('drop table mojo_mysql1') unless $ENV{TEST_KEEP_DB};

done_testing;
