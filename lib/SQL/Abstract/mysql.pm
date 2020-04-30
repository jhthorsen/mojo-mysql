package SQL::Abstract::mysql;
use Mojo::Base 'SQL::Abstract';

BEGIN { *puke = \&SQL::Abstract::puke }

sub insert {
  my $self    = shift;
  my $table   = $self->_table($_[0]);
  my $data    = $_[1] || return;
  my $options = $_[2] || {};

  my ($sql, @bind) = $self->SUPER::insert(@_);
  my $command;

  # options
  if (exists $options->{on_conflict}) {
    my $on_conflict = $options->{on_conflict} // '';
    my %commands = (ignore => 'insert ignore', replace => 'replace');
    if (ref $on_conflict eq 'HASH') {
      $command = 'insert';
      my ($sql2, @bind2) = $self->_update_set_values($on_conflict);
      $sql .= $self->_sqlcase(' on duplicate key update ') . $sql2;
      push @bind, @bind2;
    }
    else {
      $command = $commands{$on_conflict} or puke qq{on_conflict value "$on_conflict" is not allowed};
    }
    my $replace = $self->_sqlcase($command);
    $sql =~ s/^(\w+)/$replace/;
  }

  return wantarray ? ($sql, @bind) : $sql;
}

sub _order_by {
  my ($self, $options) = @_;

  # Legacy
  return $self->SUPER::_order_by($options) if ref $options ne 'HASH' or grep {/^-(?:desc|asc)/i} keys %$options;

  # GROUP BY
  my $sql = '';
  my @bind;
  if (defined(my $group = $options->{group_by})) {
    my $group_sql;
    $self->_SWITCH_refkind(
      $group => {
        ARRAYREF => sub {
          $group_sql = join ', ', map { $self->_quote($_) } @$group;
        },
        SCALARREF => sub { $group_sql = $$group }
      }
    );
    $sql .= $self->_sqlcase(' group by ') . $group_sql;
  }

  # HAVING
  if (defined(my $having = $options->{having})) {
    my ($having_sql, @having_bind) = $self->_recurse_where($having);
    $sql .= $self->_sqlcase(' having ') . $having_sql;
    push @bind, @having_bind;
  }

  # ORDER BY
  $sql .= $self->_order_by($options->{order_by}) if defined $options->{order_by};

  # LIMIT
  if (defined $options->{limit}) {
    $sql .= $self->_sqlcase(' limit ') . '?';
    push @bind, $options->{limit};
  }

  # OFFSET
  if (defined $options->{offset}) {
    $sql .= $self->_sqlcase(' offset ') . '?';
    push @bind, $options->{offset};
  }

  # FOR
  if (defined(my $for = $options->{for})) {
    my $for_sql;
    $self->_SWITCH_refkind(
      $for => {
        SCALAR => sub {
          my %commands = (update => 'for update', share => 'lock in share mode');
          my $command  = $commands{$for} or puke qq{for value "$for" is not allowed};
          $for_sql = $self->_sqlcase($command);
        },
        SCALARREF => sub { $for_sql = "FOR $$for" }
      }
    );
    $sql .= " $for_sql";
  }

  return $sql, @bind;
}

sub _select_fields {
  my ($self, $fields) = @_;

  return $fields unless ref $fields eq 'ARRAY';

  my (@fields, @bind);
  for my $field (@$fields) {
    $self->_SWITCH_refkind(
      $field => {
        ARRAYREF => sub {
          puke 'field alias must be in the form [$name => $alias]' if @$field < 2;
          push @fields, $self->_quote($field->[0]) . $self->_sqlcase(' as ') . $self->_quote($field->[1]);
        },
        ARRAYREFREF => sub {
          push @fields, shift @$$field;
          push @bind,   @$$field;
        },
        SCALARREF => sub { push @fields, $$field },
        FALLBACK  => sub { push @fields, $self->_quote($field) }
      }
    );
  }

  return join(', ', @fields), @bind;
}

sub _table {
  my ($self, $table) = @_;

  return $self->SUPER::_table($table) unless ref $table eq 'ARRAY';

  my (@tables, @joins);
  for my $jt (@$table) {
    if   (ref $jt eq 'ARRAY') { push @joins,  $jt }
    else                      { push @tables, $jt }
  }

  my $sql = $self->SUPER::_table(\@tables);
  my $sep = $self->{name_sep} // '';
  for my $join (@joins) {

    my $type = '';
    if ($join->[0] =~ /^-(.+)/) {
      $type = " $1";
      shift @$join;
    }

    my $name = shift @$join;
    $sql .= $self->_sqlcase("$type join ") . $self->_quote($name);

    # NATURAL JOIN
    if ($type eq ' natural') {
      puke 'natural join must be in the form [-natural => $table]' if @$join;
    }

    # JOIN USING
    elsif (@$join == 1) {
      $sql .= $self->_sqlcase(' using (') . $self->_quote($join->[0]) . ')';
    }

    # others
    else {
      puke 'join must be in the form [$table, $fk => $pk]' if @$join < 2;
      puke 'join requires an even number of keys' if @$join % 2;

      my @keys;
      while (my ($fk, $pk) = splice @$join, 0, 2) {
        push @keys,
          $self->_quote(index($fk, $sep) > 0 ? $fk : "$name.$fk") . ' = '
          . $self->_quote(index($pk, $sep) > 0 ? $pk : "$tables[0].$pk");
      }

      $sql .= $self->_sqlcase(' on ') . '(' . join($self->_sqlcase(' and '), @keys) . ')';
    }

  }

  return $sql;
}

1;

=encoding utf8

=head1 NAME

SQL::Abstract::mysql - Generate SQL from Perl data structures for MySQL and MariaDB

=head1 SYNOPSIS

  use SQL::Abstract::mysql;

  my $abstract = SQL::Abstract::mysql->new(quote_char => chr(96), name_sep => '.');
  # The same as
  use Mojo::mysql;
  my $mysql = Mojo::mysql->new;
  my $abstract = $mysql->abstract;

  say $abstract->insert('some_table', \%some_values, \%some_options);
  say $abstract->select('some_table');

=head1 DESCRIPTION

L<SQL::Abstract::mysql> extends L<SQL::Abstract> with a few MySQL / MariaDB
features used by L<Mojo::mysql>. It was inspired by L<SQL::Abstract::Pg>.

=head1 METHODS

L<SQL::Abstract::mysql> inherits all methods from L<SQL::Abstract>.

=head2 insert

  my ($stmt, @bind) = $abstract->insert($table, \@values || \%fieldvals, \%options);

This method extends L<SQL::Abstract/insert> with the following functionality:

=head3 ON CONFLICT

The C<on_conflict> option can be used to generate C<INSERT IGNORE>, C<REPLACE> and
C<INSERT ... ON DUPLICATE KEY UPDATE> queries.
So far C<'ignore'> to pass C<INSERT IGNORE>, C<'replace'> to pass C<REPLACE> and
hash references to pass C<UPDATE> with conflict targets are supported.

  # "insert ignore into t (id, a) values (123, 'b')"
  $abstract->insert('t', {id => 123, a => 'b'}, {on_conflict => 'ignore'});

  # "replace into t (id, a) values (123, 'b')"
  $abstract->insert('t', {id => 123, a => 'b'}, {on_conflict => 'replace'});

  # "insert into t (id, a) values (123, 'b') on duplicate key update c='d'"
  $abstract->insert('t', {id => 123, a => 'b'}, {on_conflict => {c => 'd'}});

=head2 select

  my ($stmt, @bind) = $abstract->select($source, $fields, $where, $order);
  my ($stmt, @bind) = $abstract->select($source, $fields, $where, \%options);

This method extends L<SQL::Abstract/select> with the following functionality:

=head3 AS

The C<$fields> argument accepts array references containing array references
with field names and aliases, as well as array references containing scalar
references to pass literal SQL and array reference references to pass literal
SQL with bind values.

  # "select foo as bar from some_table"
  $abstract->select('some_table', [[foo => 'bar']]);

  # "select foo, bar as baz, yada from some_table"
  $abstract->select('some_table', ['foo', [bar => 'baz'], 'yada']);

  # "select extract(epoch from foo) as foo, bar from some_table"
  $abstract->select('some_table', [\'extract(epoch from foo) as foo', 'bar']);

  # "select 'test' as foo, bar from some_table"
  $abstract->select('some_table', [\['? as foo', 'test'], 'bar']);

=head3 JOIN

The C<$source> argument accepts array references containing not only table
names, but also array references with tables to generate C<JOIN> clauses for.

  # "select * from foo join bar on (bar.foo_id = foo.id)"
  $abstract->select(['foo', ['bar', foo_id => 'id']]);

  # "select * from foo join bar on (foo.id = bar.foo_id)"
  $abstract->select(['foo', ['bar', 'foo.id' => 'bar.foo_id']]);

  # -left, -right, -inner
  # "select * from foo left join bar on (bar.foo_id = foo.id)"
  $abstract->select(['foo', [-left => 'bar', foo_id => 'id']]);

  # -natural
  # "select * from foo natural join bar"
  $abstract->select(['foo', [-natural => 'bar']]);

  # join using
  # "select * from foo join bar using (foo_id)"
  $abstract->select(['foo', [bar => 'foo_id']]);

  # more than one table
  # "select * from foo join bar on (bar.foo_id = foo.id) join baz on (baz.foo_id = foo.id)"
  $abstract->select(['foo', ['bar', foo_id => 'id'], ['baz', foo_id => 'id']]);

  # more than one field
  # "select * from foo left join bar on (bar.foo_id = foo.id and bar.foo_id2 = foo.id2)"
  $abstract->select(['foo', [-left => 'bar', foo_id => 'id', foo_id2 => 'id2']]);

=head3 ORDER BY

In addition to the C<$order> argument accepted by L<SQL::Abstract> you can pass
a hash reference with various options. This includes C<order_by>, which takes
the same values as the C<$order> argument.

  # "select * from some_table order by foo desc"
  $abstract->select('some_table', '*', undef, {order_by => {-desc => 'foo'}});

=head3 LIMIT / OFFSET

The C<limit> and C<offset> options can be used to generate C<SELECT> queries
with C<LIMIT> and C<OFFSET> clauses.

  # "select * from some_table limit 10"
  $abstract->select('some_table', '*', undef, {limit => 10});

  # "select * from some_table offset 5"
  $abstract->select('some_table', '*', undef, {offset => 5});

  # "select * from some_table limit 10 offset 5"
  $abstract->select('some_table', '*', undef, {limit => 10, offset => 5});

=head3 GROUP BY

The C<group_by> option can be used to generate C<SELECT> queries with C<GROUP
BY> clauses. So far array references to pass a list of fields and scalar
references to pass literal SQL are supported.

  # "select * from some_table group by foo, bar"
  $abstract->select('some_table', '*', undef, {group_by => ['foo', 'bar']});

  # "select * from some_table group by foo, bar"
  $abstract->select('some_table', '*', undef, {group_by => \'foo, bar'});

=head3 HAVING

The C<having> option can be used to generate C<SELECT> queries with C<HAVING>
clauses, which takes the same values as the C<$where> argument.

  # "select * from t group by a having b = 'c'"
  $abstract->select('t', '*', undef, {group_by => ['a'], having => {b => 'c'}});

=head3 FOR

The C<for> option can be used to generate C<SELECT> queries with C<FOR UPDATE>
or C<LOCK IN SHARE MODE> clauses.  So far the scalar values C<update> and
C<share> and scalar references to pass literal SQL are supported.

  # "select * from some_table for update"
  $abstract->select('some_table', '*', undef, {for => 'update'});

  # "select * from some_table lock in share mode"
  $abstract->select('some_table', '*', undef, {for => 'share'});

  # "select * from some_table for share"
  $abstract->select('some_table', '*', undef, {for => \'share'});

  # "select * from some_table for update skip locked"
  $abstract->select('some_table', '*', undef, {for => \'update skip locked'});

=head1 SEE ALSO

L<Mojo::mysql>, L<SQL::Abstract::Pg>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
