use Mojo::Base -strict;

use Test::More;
use Mojo::mysql;
use SQL::Abstract::Test import => ['is_same_sql_bind'];

note 'Basics';
my $mysql    = Mojo::mysql->new;
my $abstract = $mysql->abstract;
is_query([$abstract->insert('foo', {bar => 'baz'})], ['INSERT INTO `foo` ( `bar`) VALUES ( ? )', 'baz'], 'right query');
is_query([$abstract->select('foo', '*')], ['SELECT * FROM `foo`'], 'right query');
is_query([$abstract->select(['foo', 'bar', 'baz'])], ['SELECT * FROM `foo`, `bar`, `baz`'], 'right query');
is_query(
  [$abstract->select(['wibble.foo', 'wobble.bar', 'wubble.baz'])],
  ['SELECT * FROM `wibble`.`foo`, `wobble`.`bar`, `wubble`.`baz`'],
  'right query'
);

my (@sql, $result);

note 'on conflict: INSERT IGNORE';
@sql = $abstract->insert('foo', {bar => 'baz'}, {on_conflict => 'ignore'});
is_query(\@sql, ['INSERT IGNORE INTO `foo` ( `bar`) VALUES ( ? )', 'baz'], 'right query');

note 'on conflict: REPLACE';
@sql = $abstract->insert('foo', {bar => 'baz'}, {on_conflict => 'replace'});
is_query(\@sql, ['REPLACE INTO `foo` ( `bar`) VALUES ( ? )', 'baz'], 'right query');

note 'on conflict: ON DUPLICATE KEY UPDATE';
@sql = $abstract->insert('foo', {bar => 'baz'}, {on_conflict => {c => 'd'}});
is_query(\@sql, ['INSERT INTO `foo` ( `bar`) VALUES ( ? ) ON DUPLICATE KEY UPDATE `c` = ?', 'baz', 'd'], 'right query');

note 'on conflict (unsupported value)';
eval { $abstract->insert('foo', {bar => 'baz'}, {on_conflict => 'do something'}) };
like $@, qr/on_conflict value "do something" is not allowed/, 'right error';

eval { $abstract->insert('foo', {bar => 'baz'}, {on_conflict => undef}) };
like $@, qr/on_conflict value "" is not allowed/, 'right error';

note 'SELECT AS';
is_query(
  [$abstract->select('foo', [[bar => 'wibble'], [baz => 'wobble'], 'yada'])],
  ['SELECT `bar` AS `wibble`, `baz` AS `wobble`, `yada` FROM `foo`'],
  'right query'
);

note 'ORDER BY';
@sql = $abstract->select('foo', '*', {bar => 'baz'}, {-desc => 'yada'});
is_query(\@sql, ['SELECT * FROM `foo` WHERE ( `bar` = ? ) ORDER BY `yada` DESC', 'baz'], 'right query');

@sql = $abstract->select('foo', '*', {bar => 'baz'}, {order_by => {-desc => 'yada'}});
is_query(\@sql, ['SELECT * FROM `foo` WHERE ( `bar` = ? ) ORDER BY `yada` DESC', 'baz'], 'right query');

note 'LIMIT, OFFSET';
@sql = $abstract->select('foo', '*', undef, {limit => 10, offset => 5});
is_query(\@sql, ['SELECT * FROM `foo` LIMIT ? OFFSET ?', 10, 5], 'right query');

note 'GROUP BY';
@sql = $abstract->select('foo', '*', undef, {group_by => \'bar, baz'});
is_query(\@sql, ['SELECT * FROM `foo` GROUP BY bar, baz'], 'right query');

@sql = $abstract->select('foo', '*', undef, {group_by => ['bar', 'baz']});
is_query(\@sql, ['SELECT * FROM `foo` GROUP BY `bar`, `baz`'], 'right query');

note 'HAVING';
@sql = $abstract->select('foo', '*', undef, {group_by => ['bar'], having => {baz => 'yada'}});
is_query(\@sql, ['SELECT * FROM `foo` GROUP BY `bar` HAVING `baz` = ?', 'yada'], 'right query');

@sql = $abstract->select('foo', '*', {bar => {'>' => 'baz'}}, {group_by => ['bar'], having => {baz => {'<' => 'bar'}}});
$result = ['SELECT * FROM `foo` WHERE ( `bar` > ? ) GROUP BY `bar` HAVING `baz` < ?', 'baz', 'bar'];
is_query(\@sql, $result, 'right query');

note 'GROUP BY (unsupported value)';
eval { $abstract->select('foo', '*', undef, {group_by => {}}) };
like $@, qr/HASHREF/, 'right error';

note 'for: FOR UPDATE';
@sql = $abstract->select('foo', '*', undef, {for => 'update'});
is_query(\@sql, ['SELECT * FROM `foo` FOR UPDATE'], 'right query');

note 'for: LOCK IN SHARE MODE';
@sql = $abstract->select('foo', '*', undef, {for => 'share'});
is_query(\@sql, ['SELECT * FROM `foo` LOCK IN SHARE MODE'], 'right query');

@sql = $abstract->select('foo', '*', undef, {for => \'SHARE'});
is_query(\@sql, ['SELECT * FROM `foo` FOR SHARE'], 'right query');

note 'for (unsupported value)';
eval { $abstract->select('foo', '*', undef, {for => 'update skip locked'}) };
like $@, qr/for value "update skip locked" is not allowed/, 'right error';

eval { $abstract->select('foo', '*', undef, {for => []}) };
like $@, qr/ARRAYREF/, 'right error';

note 'JOIN: single field';
@sql = $abstract->select(['foo', ['bar', foo_id => 'id']]);
is_query(\@sql, ['SELECT * FROM `foo` JOIN `bar` ON (`bar`.`foo_id` = `foo`.`id`)'], 'right query');

@sql = $abstract->select(['foo', ['bar', 'foo.id' => 'bar.foo_id']]);
is_query(\@sql, ['SELECT * FROM `foo` JOIN `bar` ON (`foo`.`id` = `bar`.`foo_id`)'], 'right query');

note 'JOIN: multiple fields';
@sql = $abstract->select(['foo', ['bar', 'foo.id' => 'bar.foo_id', 'foo.id2' => 'bar.foo_id2']]);
is_query(\@sql,
  ['SELECT * FROM `foo` JOIN `bar` ON (`foo`.`id` = `bar`.`foo_id`' . ' AND `foo`.`id2` = `bar`.`foo_id2`' . ')'],
  'right query');

note 'JOIN: multiple tables';
@sql = $abstract->select(['foo', ['bar', foo_id => 'id'], ['baz', foo_id => 'id']]);
is_query(\@sql,
  ['SELECT * FROM `foo` JOIN `bar` ON (`bar`.`foo_id` = `foo`.`id`) JOIN `baz` ON (`baz`.`foo_id` = `foo`.`id`)'],
  'right query');

note 'LEFT JOIN';
@sql = $abstract->select(['foo', [-left => 'bar', foo_id => 'id']]);
is_query(\@sql, ['SELECT * FROM `foo` LEFT JOIN `bar` ON (`bar`.`foo_id` = `foo`.`id`)'], 'right query');

note 'LEFT JOIN: multiple fields';
@sql = $abstract->select(['foo', [-left => 'bar', foo_id => 'id', foo_id2 => 'id2', foo_id3 => 'id3']]);
is_query(
  \@sql,
  [
        'SELECT * FROM `foo` LEFT JOIN `bar` ON (`bar`.`foo_id` = `foo`.`id`'
      . ' AND `bar`.`foo_id2` = `foo`.`id2` AND `bar`.`foo_id3` = `foo`.`id3`)'
  ],
  'right query'
);

note 'RIGHT JOIN';
@sql = $abstract->select(['foo', [-right => 'bar', foo_id => 'id']]);
is_query(\@sql, ['SELECT * FROM `foo` RIGHT JOIN `bar` ON (`bar`.`foo_id` = `foo`.`id`)'], 'right query');

note 'INNER JOIN';
@sql = $abstract->select(['foo', [-inner => 'bar', foo_id => 'id']]);
is_query(\@sql, ['SELECT * FROM `foo` INNER JOIN `bar` ON (`bar`.`foo_id` = `foo`.`id`)'], 'right query');

note 'NATURAL JOIN';
@sql = $abstract->select(['foo', [-natural => 'bar']]);
is_query(\@sql, ['SELECT * FROM `foo` NATURAL JOIN `bar`'], 'right query');

note 'JOIN USING';
@sql = $abstract->select(['foo', [bar => 'foo_id']]);
is_query(\@sql, ['SELECT * FROM `foo` JOIN `bar` USING (`foo_id`)'], 'right query');

note 'JOIN: unsupported value';
eval { $abstract->select(['foo', ['bar']]) };
like $@, qr/join must be in the form \[\$table, \$fk => \$pk\]/, 'right error for missing keys';

eval { $abstract->select(['foo', ['bar', foo_id => 'id', 'id2']]) };
like $@, qr/join requires an even number of keys/, 'right error for uneven number of keys';

eval { $abstract->select(['foo', [-natural => 'bar', 'foo_id']]) };
like $@, qr/natural join must be in the form \[-natural => \$table\]/, 'right error for wrong natural join';

done_testing;

sub is_query {
  my ($got, $want, $msg) = @_;
  my $got_sql  = shift @$got;
  my $want_sql = shift @$want;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  is_same_sql_bind $got_sql, $got, $want_sql, $want, $msg;
}
