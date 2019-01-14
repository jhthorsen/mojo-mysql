use Mojo::Base -strict;

use Mojo::JSON;
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
  plan skip_all => 'no JSON support';
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

# extended JSON

# INSERT

ok $db->query('delete from mojo_json_test'), 'clean db';
my @testvalues = (
  {id => 1, name => 'Katniss Everdeen', j => {district => 12, tournament => 74,}},
  {
    id   => 2,
    name => 'Peeta Mellark',
    j    => {district => 12, occupation => 'baker', skills => 'camouflage', tournament => 74,}
  },
  {id => 3, name => 'Primrose Everdeen',  j => {district => 12, skills     => 'healing',}},
  {id => 4, name => 'Haymitch Abernathy', j => {district => 12, tournament => 50,}},
  {id => 5, name => 'Gale Hawthorne',     j => {district => 12, occupation => 'miner',}},
);

for (@testvalues) {
  ok $db->insert('mojo_json_test', $_), "insert $_->{name}";
}

# SELECT

is_deeply $db->select('mojo_json_test', '*', {id => 1})->expand->hash, $testvalues[0], 'content for Katniss';

is_deeply $db->select('mojo_json_test', ['name', 'j->>district', 'j->>occupation'], {id => 2})->hash,
  {district => 12, name => 'Peeta Mellark', occupation => 'baker'}, 'details for Peeta';

is_deeply $db->select('mojo_json_test', ['name'], {'j->>tournament' => 50})->hash, {name => 'Haymitch Abernathy'},
  'Haymitch was in 50';

is $db->select('mojo_json_test', ['name'], {-e => 'j->skills'})->text, "Peeta Mellark\nPrimrose Everdeen\n",
  'Peeta and Prim have skills';

is $db->select('mojo_json_test', ['name'], {-ne => 'j->tournament'})->text, "Primrose Everdeen\nGale Hawthorne\n",
  'Prim and Gale were not at the games';

is $db->select('mojo_json_test', ['name'], {-e => 'j->tournament'}, ['j->tournament', 'id'])->text,
  "Haymitch Abernathy\nKatniss Everdeen\nPeeta Mellark\n", 'Haymitch was at the games before Katniss and Peeta';

# UPDATE

ok $db->update('mojo_json_test', {'j->mascot' => 'Mockingjay'}, {id => 1}), 'Katniss has a mascot';
is $db->select('mojo_json_test', ['j->>mascot'], {id => 1})->array->[0], 'Mockingjay', 'it\'s a Mockingjay';

eval { ok $db->update('mojo_json_test', {'j->pet' => {name => 'Buttercup', cat => 1}}, {id => 3}), 'Prim has a pet'; };
SKIP: {
  skip 'not supported on MariaDB' if $@ =~ /MariaDB/;
  is_deeply $db->select('mojo_json_test', ['j->pet'], {id => 3})->expand->hash,
    {pet => {name => 'Buttercup', cat => 1}}, 'it\'s a cat called Buttercup';
}

ok $db->update('mojo_json_test', {'j->occupation' => undef}, {id => 5}), 'Gale quits his job';
is $db->select('mojo_json_test', ['name'], {-e => 'j->occupation'})->text, "Peeta Mellark\n", 'only Peeta has a job';

ok $db->update('mojo_json_test', {'j->district' => 13, 'j->rebel' => 1}, {id => 5}),
  'Gale moves to 13 and becomes a rebel';
is_deeply $db->select('mojo_json_test', ['j->>district', 'j->>rebel'], {id => 5})->hash, {district => 13, rebel => 1},
  'he lives in 13 and is a rebel';

# cleanup

$db->query('drop table mojo_json_test') unless $ENV{TEST_KEEP_DB};

done_testing;
