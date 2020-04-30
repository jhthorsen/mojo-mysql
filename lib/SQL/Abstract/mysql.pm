package SQL::Abstract::mysql;
use Mojo::Base 'SQL::Abstract';

BEGIN { *puke = \&SQL::Abstract::puke }

sub insert {
  my ($self, $table, $data, $options) = (shift, @_);
  my ($sql, @bind) = $self->SUPER::insert(@_);

  $self->_mysql_on_conflict(\$sql, \@bind, $options->{on_conflict} // '') if exists $options->{on_conflict};

  return wantarray ? ($sql, @bind) : $sql;
}

sub select {
  my ($self, $table, $fields) = (shift, shift, shift);

  my @b;
  $fields = $self->_mysql_array_fields(\@b, $fields) if ref $fields eq 'ARRAY';

  my ($sql, @bind) = $self->SUPER::select($table, $fields, @_);
  return wantarray ? ($sql, @b, @bind) : $sql;
}

sub where {
  my ($self, $where, $order) = (shift, shift, shift);
  my $options = {};

  if (ref $order eq 'HASH' and !grep /^-(?:desc|asc)/i, keys %$order) {
    $options = $order;
    $order   = $order->{order_by};
  }

  my ($sql, @bind) = $self->SUPER::where($where, $order, @_);
  $self->_mysql_group_by(\$sql, \@bind, $options->{group_by}) if defined $options->{group_by};
  $self->_mysql_having(\$sql, \@bind, $options->{having})     if defined $options->{having};
  $self->_mysql_limit(\$sql, \@bind, $options->{limit})       if defined $options->{limit};
  $self->_mysql_offset(\$sql, \@bind, $options->{offset})     if defined $options->{offset};
  $self->_mysql_for(\$sql, \@bind, $options->{for})           if defined $options->{for};

  return wantarray ? ($sql, @bind) : $sql;
}

sub _mysql_array_fields {
  my ($self, $bind, $fields) = @_;

  return join ', ', map {
    my $field = $_;
    $self->_SWITCH_refkind(
      $field => {
        ARRAYREF => sub {
          puke 'field alias must be in the form [$name => $alias]' if @$field < 2;
          $self->_quote($field->[0]) . $self->_sqlcase(' as ') . $self->_quote($field->[1]);
        },
        ARRAYREFREF => sub {
          my $name = shift @$$field;
          push @$bind, @$$field;
          return $name;
        },
        SCALARREF => sub {$$field},
        FALLBACK  => sub { $self->_quote($field) }
      }
    );
  } @$fields;
}

sub _mysql_for {
  my ($self, $sql, $bind, $for) = @_;

  $$sql .= $self->_SWITCH_refkind(
    $for => {
      SCALAR => sub {
        return $self->_sqlcase(' lock in share mode') if $for eq 'share';
        return $self->_sqlcase(' for update')         if $for eq 'update';
        puke qq{for value "$for" is not allowed};
      },
      SCALARREF => sub { $self->_sqlcase(' for ') . $$for }
    }
  );
}

sub _mysql_group_by {
  my ($self, $sql, $bind, $group_by) = @_;

  $$sql .= $self->_sqlcase(' group by ') . $self->_SWITCH_refkind(
    $group_by => {
      ARRAYREF => sub {
        join ', ', map { $self->_quote($_) } @$group_by;
      },
      SCALARREF => sub {$$group_by},
    }
  );
}

sub _mysql_having {
  my ($self, $sql, $bind, $having) = @_;
  my ($s, @b) = $self->_recurse_where($having);
  $$sql .= $self->_sqlcase(' having ') . $s;
  push @$bind, @b;
}

sub _mysql_limit {
  my ($self, $sql, $bind, $limit) = @_;
  $$sql .= $self->_sqlcase(' limit ') . '?';
  push @$bind, $limit;
}

sub _mysql_offset {
  my ($self, $sql, $bind, $offset) = @_;
  $$sql .= $self->_sqlcase(' offset ') . '?';
  push @$bind, $offset;
}

sub _mysql_on_conflict {
  my ($self, $sql, $bind, $on_conflict) = @_;

  if (ref $on_conflict eq 'HASH') {
    my ($s, @b) = $self->_update_set_values($on_conflict);
    $$sql .= $self->_sqlcase(' on duplicate key update ') . $s;
    push @$bind, @b;
  }
  elsif ($on_conflict eq 'ignore') {
    $$sql =~ s!^(\w+)!{$self->_sqlcase('insert ignore')}!e;
  }
  elsif ($on_conflict eq 'replace') {
    $$sql =~ s!^(\w+)!{$self->_sqlcase('replace')}!e;
  }
  else {
    puke qq{on_conflict value "$on_conflict" is not allowed};
  }
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
      $type = $1;
      shift @$join;
    }

    my $name = shift @$join;
    $sql .= $self->_sqlcase(" $type join ") . $self->_quote($name);

    # NATURAL JOIN
    if ($type eq 'natural') {
      puke 'natural join must be in the form [-natural => $table]' if @$join;
    }

    # JOIN USING
    elsif (@$join == 1) {
      $sql .= $self->_sqlcase(' using (') . $self->_quote($join->[0]) . ')';
    }

    # others
    else {
      puke 'join must be in the form [$table, $fk => $pk]' if @$join < 2;
      puke 'join requires an even number of keys'          if @$join % 2;

      my @keys;
      while (my ($fk, $pk) = splice @$join, 0, 2) {
        push @keys,
          $self->_quote(index($fk, $sep) > 0   ? $fk : "$name.$fk") . ' = '
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

=head2 where

  my ($stmt, @bind) = $abstract->where($where, \%options);

This method extends L<SQL::Abstract/where> with the following functionality:

=head3 GROUP BY

The C<group_by> option can be used to generate C<SELECT> queries with C<GROUP
BY> clauses. So far array references to pass a list of fields and scalar
references to pass literal SQL are supported.

  # "select * from some_table group by foo, bar"
  $abstract->select('some_table', '*', undef, {group_by => ['foo', 'bar']});

  # "select * from some_table group by foo, bar"
  $abstract->select('some_table', '*', undef, {group_by => \'foo, bar'});

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

=head3 HAVING

The C<having> option can be used to generate C<SELECT> queries with C<HAVING>
clauses, which takes the same values as the C<$where> argument.

  # "select * from t group by a having b = 'c'"
  $abstract->select('t', '*', undef, {group_by => ['a'], having => {b => 'c'}});

=head3 LIMIT / OFFSET

The C<limit> and C<offset> options can be used to generate C<SELECT> queries
with C<LIMIT> and C<OFFSET> clauses.

  # "select * from some_table limit 10"
  $abstract->select('some_table', '*', undef, {limit => 10});

  # "select * from some_table offset 5"
  $abstract->select('some_table', '*', undef, {offset => 5});

  # "select * from some_table limit 10 offset 5"
  $abstract->select('some_table', '*', undef, {limit => 10, offset => 5});

=head3 ORDER BY

In addition to the C<$order> argument accepted by L<SQL::Abstract> you can pass
a hash reference with various options. This includes C<order_by>, which takes
the same values as the C<$order> argument.

  # "select * from some_table order by foo desc"
  $abstract->select('some_table', '*', undef, {order_by => {-desc => 'foo'}});

=head1 SEE ALSO

L<Mojo::mysql>, L<SQL::Abstract::Pg>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
