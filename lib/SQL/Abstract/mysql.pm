package SQL::Abstract::mysql;
use Mojo::Base 'SQL::Abstract';

use Mojo::JSON 'encode_json';

BEGIN { *puke = \&SQL::Abstract::puke }

sub new {
  my $self = shift->SUPER::new(@_);

  # -e and -ne op
  push @{$self->{unary_ops}}, {regex => qr/^e$/, handler => '_where_op_EXISTS',},
    {regex => qr/^ne$/, handler => '_where_op_NOT_EXISTS',};

  return $self;
}

sub insert {
  my $self    = shift;
  my $table   = $self->_table(shift);
  my $data    = shift || return;
  my $options = shift || {};

  my $method = $self->_METHOD_FOR_refkind('_insert', $data);
  my ($sql, @bind) = $self->$method($data);
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
  }
  else {
    $command = 'insert';
  }
  $sql = join ' ', $self->_sqlcase("$command into"), $table, $sql;

  return wantarray ? ($sql, @bind) : $sql;
}

sub _insert_value {
  my ($self, $column, $v) = @_;

  if (ref $v eq 'HASH') {

    # THINK: anything useful to do with a HASHREF ? (SQL::Abstract)
    # ANSWER: Of course, insert JSON!
    $v = encode_json($v);
  }
  return $self->SUPER::_insert_value($column, $v);
}

sub _json_extract {
  my ($self, $label, $alias) = @_;
  return $self->SUPER::_quote($label) unless $label =~ /->/;

  my ($field, $unquote, $path) = $label =~ /(.+)->([>]?)(.+)/;
  $field = $self->SUPER::_quote($field);

  my $rv = "JSON_EXTRACT($field,'\$.$path')";
  $rv = "JSON_UNQUOTE($rv)" if $unquote;

  if ($alias) {
    $path =~ /(\w+)$/;
    $rv .= " AS $self->{quote_char}$1$self->{quote_char}";
  }

  return $rv;
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
          my $command = $commands{$for} or puke qq{for value "$for" is not allowed};
          $for_sql = $self->_sqlcase($command);
        },
        SCALARREF => sub { $for_sql = "FOR $$for" }
      }
    );
    $sql .= " $for_sql";
  }

  return $sql, @bind;
}

sub _order_by_chunks {
  my ($self, $arg) = @_;
  if ($arg =~ /->/) {
    return $self->_json_extract($arg);
  }
  else {
    return $self->SUPER::_order_by_chunks($arg);
  }
}

sub _select_fields {
  my ($self, $fields) = @_;
  return $fields unless ref $fields eq 'ARRAY';

  if (grep /->/, @$fields) {
    return join ',', map { $self->_json_extract($_, 1) } @$fields;
  }
  else {
    return join ',', map { $self->_quote($_) } @$fields;
  }
}

sub _update_set_values {
  my ($self, $data) = @_;

  for my $k (sort grep /->/, keys %$data) {
    my ($label, $path) = $k =~ /(.+)->(.*)/;
    my $origin = $self->_quote($label);
    puke "you can\'t update $label and its values in the same query"
      unless ($data->{$label}->[0] || 'json') =~ /^json/i;
    if (defined $data->{$k}) {
      if ($data->{$label}->[0]) {
        puke "you can\'t update and remove values of $label in the same query"
          unless $data->{$label}->[0] =~ /^json_set/i;
      }
      else {
        $data->{$label}->[0] = $path ? $self->_sqlcase('json_set(') . "$origin)" : '?';
      }
      my $placeholder;
      if (ref $data->{$k}) {
        $data->{$k} = encode_json($data->{$k});
        $placeholder = $self->_sqlcase('cast(? as json)');
      }
      else {
        $placeholder = '?';
      }

      $data->{$label}->[0] =~ s/\)$/,'\$.$path',$placeholder)/ if $path;
      push @{$data->{$label}}, $data->{$k};
    }
    else {
      if ($data->{$label}->[0]) {
        puke "you can\'t update and remove values of $label in the same query"
          unless $data->{$label}->[0] =~ /^json_remove/i;
      }
      else {
        $data->{$label}->[0] = $self->_sqlcase('json_remove(') . "$origin)";
      }
      $data->{$label}->[0] =~ s/\)$/,'\$.$path')/;
    }
    delete $data->{$k};
  }

  return $self->SUPER::_update_set_values($data);
}

sub _where_hashpair_SCALAR {
  my ($self, $k, $v) = @_;

  if ($k =~ /->/) {
    $k = \$self->_json_extract($k);
  }

  return $self->SUPER::_where_hashpair_SCALAR($k, $v);
}

sub _where_op_EXISTS {
  my ($self, $op, $v) = @_;

  $v =~ /(.+)->(.+)/ or puke "-$op => $v doesn't work, use $op => $v->key1.key2 instead";

  return $self->_sqlcase('json_contains_path(') . $self->_quote($1) . ",'one','\$.$2')";
}

sub _where_op_NOT_EXISTS {
  my $self = shift;
  return $self->_sqlcase('not ') . $self->_where_op_EXISTS(@_);
}

1;

=encoding utf8

=head1 NAME

SQL::Abstract::mysql - Generate SQL from Perl data structures for MySQL and MariaDB

=head1 SYNOPSIS

  use SQL::Abstract::mysql;

  my $abstract = SQL::Abstract::mysql->new(quote_char => chr(96), name_sep => '.');

  say $abstract->insert('some_table', \%some_values, \%some_options);
  say $abstract->update('some_table', \%some_values, \%some_options);
  say $abstract->select('some_table', \@some_fields, \%some_filters, \%some_options);

=head1 DESCRIPTION

L<SQL::Abstract::mysql> extends L<SQL::Abstract> with a few MySQL / MariaDB
features used by L<Mojo::mysql>. It was inspired by L<SQL::Abstract::Pg>.

=head1 CONSTRUCTOR

=head2 new

  my $abstract = SQL::Abstract::mysql->new(quote_char => chr(96), name_sep => '.');

Creates a new L<SQL::Abstract::mysql>. The same as:

  use Mojo::mysql;
  my $mysql = Mojo::mysql->new;
  my $abstract = $mysql->abstract;

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

  # "select * from a join b on (b.a_id = a.id) join c on (c.a_id = a.id)"
  $abstract->select(['a', ['b', a_id => 'id'], ['c', a_id => 'id']]);

  # "select * from foo left join bar on (bar.foo_id = foo.id)"
  $abstract->select(['foo', [-left => 'bar', foo_id => 'id']]);

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

=head1 NESTED DATA (JSON)

=head2 arrow operator

C<SQL::Abstract::mysql> generates queries to manipulate nested data in databases
that support JSON (starting with MySQL 5.7 and MariaDB 10.2).

Paths to values are represented with an arrow as C<< table.field->path.to.value >>.
If data is read, there is a distinction between single and double arrows.
C<< field->key >> returns the object for a given key, C<< field->>key >> its value.

=head2 insert nested data

To insert data, hash references can be passed directly to L</insert>.

  my %data = (field1 => 'value1', document => {...}, ...);
  $abstract->insert('some_table', \%data);

=head2 select and filter nested data

L<Select|/select> queries with arrow operators return hash references with the selected values
at the first level.

  # returns {key1 => 'value1', key2 => {...}}
  $abstract->select('some_table', ['document->>key1', 'document->key2']);

Paths are valid as filters too.

  # key1 == 50
  $abstract->select('some_table', '*', {'document->>key1' => 50});
  # key1 exists
  $abstract->select('some_table', '*', {-e => 'document->key1'});
  # key1 doesn't exist
  $abstract->select('some_table', '*', {-ne => 'document->key1'});

In the same way they can be used to sort the result.

  # ordered by the value of key1
  $abstract->select('some_table', '*', undef, {order_by => 'document->>key1'});

=head2 update keys and values

Single keys and values are directly accessible, without the need to read and write the
whole data structure.

  # 'new value' for key1
  $abstract->update('some_table', {'document->key1' => 'new value'});
  # new object for key2; not working on MariaDB
  $abstract->update('some_table', {'document->key2' => \%new_object});
  # remove key3, don't combine with the above
  $abstract->update('some_table', {'document->key3' => undef});

To replace the content of a field a the top level, use an arrow without path.

  # add new document; not working on MariaDB
  $abstract->update('some_table', {'document->' => \%new_document});

=head1 SEE ALSO

L<Mojo::mysql>, L<SQL::Abstract::Pg>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
