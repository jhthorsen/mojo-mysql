use Mojo::Base -strict;

use Test::More;
use Mojo::mysql;

note 'Basics';
my $mysql    = Mojo::mysql->new;
my $abstract = $mysql->abstract;
is_deeply [$abstract->insert('foo', {bar => 'baz'})], ['INSERT INTO `foo` ( `bar`) VALUES ( ? )', 'baz'], 'right query';
is_deeply [$abstract->select('foo', '*')], ['SELECT * FROM `foo`'], 'right query';
is_deeply [$abstract->select(['foo', 'bar', 'baz'])], ['SELECT * FROM `foo`, `bar`, `baz`'], 'right query';
is_deeply [$abstract->select(['wibble.foo', 'wobble.bar', 'wubble.baz'])],
  ['SELECT * FROM `wibble`.`foo`, `wobble`.`bar`, `wubble`.`baz`'], 'right query';

my (@sql, $result);

note 'on conflict: INSERT IGNORE';
@sql = $abstract->insert('foo', {bar => 'baz'}, {on_conflict => 'ignore'});
is_deeply \@sql, ['INSERT IGNORE INTO `foo` ( `bar`) VALUES ( ? )', 'baz'], 'right query';

note 'on conflict: REPLACE';
@sql = $abstract->insert('foo', {bar => 'baz'}, {on_conflict => 'replace'});
is_deeply \@sql, ['REPLACE INTO `foo` ( `bar`) VALUES ( ? )', 'baz'], 'right query';

note 'on conflict: ON DUPLICATE KEY UPDATE';
@sql = $abstract->insert('foo', {bar => 'baz'}, {on_conflict => {c => 'd'}});
is_deeply \@sql, ['INSERT INTO `foo` ( `bar`) VALUES ( ? ) ON DUPLICATE KEY UPDATE `c` = ?', 'baz', 'd'], 'right query';

note 'on conflict (unsupported value)';
eval { $abstract->insert('foo', {bar => 'baz'}, {on_conflict => 'do something'}) };
like $@, qr/on_conflict value "do something" is not allowed/, 'right error';

eval { $abstract->insert('foo', {bar => 'baz'}, {on_conflict => undef}) };
like $@, qr/on_conflict value "" is not allowed/, 'right error';

note 'ORDER BY';
@sql = $abstract->select('foo', '*', {bar => 'baz'}, {-desc => 'yada'});
is_deeply \@sql, ['SELECT * FROM `foo` WHERE ( `bar` = ? ) ORDER BY `yada` DESC', 'baz'], 'right query';

@sql = $abstract->select('foo', '*', {bar => 'baz'}, {order_by => {-desc => 'yada'}});
is_deeply \@sql, ['SELECT * FROM `foo` WHERE ( `bar` = ? ) ORDER BY `yada` DESC', 'baz'], 'right query';

note 'LIMIT, OFFSET';
@sql = $abstract->select('foo', '*', undef, {limit => 10, offset => 5});
is_deeply \@sql, ['SELECT * FROM `foo` LIMIT ? OFFSET ?', 10, 5], 'right query';

note 'GROUP BY';
@sql = $abstract->select('foo', '*', undef, {group_by => \'bar, baz'});
is_deeply \@sql, ['SELECT * FROM `foo` GROUP BY bar, baz'], 'right query';

@sql = $abstract->select('foo', '*', undef, {group_by => ['bar', 'baz']});
is_deeply \@sql, ['SELECT * FROM `foo` GROUP BY `bar`, `baz`'], 'right query';

note 'HAVING';
@sql = $abstract->select('foo', '*', undef, {group_by => ['bar'], having => {baz => 'yada'}});
is_deeply \@sql, ['SELECT * FROM `foo` GROUP BY `bar` HAVING `baz` = ?', 'yada'], 'right query';

@sql = $abstract->select('foo', '*', {bar => {'>' => 'baz'}}, {group_by => ['bar'], having => {baz => {'<' => 'bar'}}});
$result = ['SELECT * FROM `foo` WHERE ( `bar` > ? ) GROUP BY `bar` HAVING `baz` < ?', 'baz', 'bar'];
is_deeply \@sql, $result, 'right query';

note 'GROUP BY (unsupported value)';
eval { $abstract->select('foo', '*', undef, {group_by => {}}) };
like $@, qr/HASHREF/, 'right error';

note 'for: FOR UPDATE';
@sql = $abstract->select('foo', '*', undef, {for => 'update'});
is_deeply \@sql, ['SELECT * FROM `foo` FOR UPDATE'], 'right query';

note 'for: LOCK IN SHARE MODE';
@sql = $abstract->select('foo', '*', undef, {for => 'share'});
is_deeply \@sql, ['SELECT * FROM `foo` LOCK IN SHARE MODE'], 'right query';

@sql = $abstract->select('foo', '*', undef, {for => \'SHARE'});
is_deeply \@sql, ['SELECT * FROM `foo` FOR SHARE'], 'right query';

note 'for (unsupported value)';
eval { $abstract->select('foo', '*', undef, {for => 'update skip locked'}) };
like $@, qr/for value "update skip locked" is not allowed/, 'right error';

eval { $abstract->select('foo', '*', undef, {for => []}) };
like $@, qr/ARRAYREF/, 'right error';

note 'JSON: INSERT';

@sql = $abstract->insert('foo', {bar => 'baz', yada => {wibble => 'wobble'}});
$result = [q|INSERT INTO `foo` ( `bar`, `yada`) VALUES ( ?, ? )|, 'baz', '{"wibble":"wobble"}'];
is_deeply \@sql, $result, 'right query';

note 'JSON: SELECT';

@sql = $abstract->select('foo', ['bar', 'bar->baz', 'bar->>baz.yada']);
$result = [
  q|SELECT `bar`,JSON_EXTRACT(`bar`,'$.baz') AS `baz`,JSON_UNQUOTE(JSON_EXTRACT(`bar`,'$.baz.yada')) AS `yada` FROM `foo`|,
];
is_deeply \@sql, $result, 'right query';

@sql = $abstract->select('foo', '*', {'bar->>baz.yada' => 'wibble'});
$result = [q|SELECT * FROM `foo` WHERE ( JSON_UNQUOTE(JSON_EXTRACT(`bar`,'$.baz.yada')) = ? )|, 'wibble',];
is_deeply \@sql, $result, 'right query';

@sql = $abstract->select('foo', '*', {-e => 'bar->baz.yada'});
$result = [q|SELECT * FROM `foo` WHERE ( JSON_CONTAINS_PATH(`bar`,'one','$.baz.yada') )|,];
is_deeply \@sql, $result, 'right query';

@sql = $abstract->select('foo', '*', {-ne => 'bar->baz.yada'});
$result = [q|SELECT * FROM `foo` WHERE ( NOT JSON_CONTAINS_PATH(`bar`,'one','$.baz.yada') )|,];
is_deeply \@sql, $result, 'right query';

@sql = $abstract->select('foo', '*', undef, [ 'bar->>baz' ]);
$result = [q|SELECT * FROM `foo` ORDER BY JSON_UNQUOTE(JSON_EXTRACT(`bar`,'$.baz'))|,];
is_deeply \@sql, $result, 'right query';

note 'JSON: SELECT, unsupported value';

eval { $abstract->select('foo', '*', {-e => 'bar.baz'}) };
like $@, qr/-e => bar.baz doesn't work/, 'right error';

eval { $abstract->select('foo', '*', {-ne => 'bar.baz'}) };
like $@, qr/-ne => bar.baz doesn't work/, 'right error';

note 'JSON: UPDATE';

@sql = $abstract->update('foo', {'bar->baz.yada' => 'wibble'});
$result = [q|UPDATE `foo` SET `bar` = JSON_SET(`bar`,'$.baz.yada',?)|, 'wibble'];
is_deeply \@sql, $result, 'right query';

@sql = $abstract->update('foo', {'bar->baz.yada' => {wibble => 'wobble'}});
$result = [q|UPDATE `foo` SET `bar` = JSON_SET(`bar`,'$.baz.yada',CAST(? AS JSON))|, '{"wibble":"wobble"}'];
is_deeply \@sql, $result, 'right query';

@sql = $abstract->update('foo', {'bar->baz' => 'wibble', 'bar->yada' => 'wobble'});
$result = [q|UPDATE `foo` SET `bar` = JSON_SET(`bar`,'$.baz',?,'$.yada',?)|, 'wibble', 'wobble'];
is_deeply \@sql, $result, 'right query';

@sql = $abstract->update('foo', {'bar->' => {baz => 'yada'}});
$result = [q|UPDATE `foo` SET `bar` = ?|, '{"baz":"yada"}'];
is_deeply \@sql, $result, 'right query';

@sql = $abstract->update('foo', {'bar->baz.yada' => undef});
$result = [q|UPDATE `foo` SET `bar` = JSON_REMOVE(`bar`,'$.baz.yada')|];
is_deeply \@sql, $result, 'right query';

@sql = $abstract->update('foo', {'bar->baz' => undef, 'bar->yada' => undef});
$result = [q|UPDATE `foo` SET `bar` = JSON_REMOVE(`bar`,'$.baz','$.yada')|];
is_deeply \@sql, $result, 'right query';

note 'JSON: UPDATE, unsupported value';

eval { @sql = $abstract->update('foo', {'bar->baz' => 'wibble', 'bar->yada' => undef}) };
like $@, qr/you can't update and remove values of bar in the same query/, 'right error';

eval { @sql = $abstract->update('foo', {'bar->' => {baz => 'wibble'}, 'bar->yada' => 'wobble'}) };
like $@, qr/you can't update bar and its values in the same query/, 'right error';

done_testing;
