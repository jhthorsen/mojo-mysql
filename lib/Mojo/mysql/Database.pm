package Mojo::mysql::Database;
use Mojo::Base 'Mojo::EventEmitter';

use Carp;
use Mojo::IOLoop;
use Mojo::JSON 'to_json';
use Mojo::mysql::Results;
use Mojo::mysql::Transaction;
use Mojo::Promise;
use Mojo::Util 'monkey_patch';
use Scalar::Util 'weaken';

has [qw(dbh mysql)];
has results_class => 'Mojo::mysql::Results';

for my $name (qw(delete insert select update)) {
  monkey_patch __PACKAGE__, $name, sub {
    my $self = shift;
    my @cb   = ref $_[-1] eq 'CODE' ? pop : ();
    return $self->query($self->mysql->abstract->$name(@_), @cb);
  };
  monkey_patch __PACKAGE__, "${name}_p", sub {
    my $self = shift;
    return $self->query_p($self->mysql->abstract->$name(@_));
  };
}

sub DESTROY {
  my $self = shift;
  $self->_cleanup_sth;
  return unless (my $mysql = $self->mysql) and (my $dbh = $self->dbh);
  $mysql->_enqueue($dbh, $self->{handle});
}

sub backlog { scalar @{shift->{waiting} || []} }

sub begin {
  my $self = shift;
  my $tx   = Mojo::mysql::Transaction->new(db => $self);
  weaken $tx->{db};
  return $tx;
}

sub disconnect {
  my $self = shift;
  $self->_cleanup_sth;
  $self->_unwatch;
  $self->dbh->disconnect;
}

sub pid { $_[0]->mysql->_dbi_attr($_[0]->dbh, 'thread_id') }

sub ping { shift->dbh->ping }

sub query {
  my ($self, $query) = (shift, shift);
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;

  # Blocking
  unless ($cb) {
    Carp::confess('Cannot perform blocking query, while waiting for async response') if $self->backlog;
    my $sth = $self->dbh->prepare($query);
    local $sth->{HandleError} = sub { $_[0] = Carp::shortmess($_[0]); 0 };
    _bind_params($sth, @_);
    my $rv  = $sth->execute;
    my $res = $self->results_class->new(db => $self, is_blocking => 1, sth => $sth);
    $res->{affected_rows} = defined $rv && $rv >= 0 ? 0 + $rv : undef;
    return $res;
  }

  # Non-blocking
  push @{$self->{waiting}}, {args => [@_], err => Carp::shortmess('__MSG__'), cb => $cb, query => $query};
  $self->$_ for qw(_next _watch);
  return $self;
}

sub query_p {
  my $self    = shift;
  my $promise = Mojo::Promise->new;
  $self->query(@_ => sub { $_[1] ? $promise->reject($_[1]) : $promise->resolve($_[2]) });
  return $promise;
}

sub quote { shift->dbh->quote(shift) }

sub quote_id { shift->dbh->quote_identifier(shift) }

sub tables {
  shift->query('show tables')->arrays->reduce(sub { push @$a, $b->[0]; $a }, []);
}

sub _bind_params {
  my $sth = shift;
  for my $i (0 .. $#_) {
    my $param = $_[$i];
    my %attrs;
    if (ref $param eq 'HASH') {
      if (exists $param->{json}) {
        $param = to_json $param->{json};
      }
      elsif (exists $param->{type} && exists $param->{value}) {
        ($param, $attrs{TYPE}) = @$param{qw(value type)};
      }
    }

    $sth->bind_param($i + 1, $param, \%attrs);
  }
  return $sth;
}

sub _cleanup_sth {
  my $self = shift;
  delete $self->{done_sth};
  $_->{cb}($self, 'Premature connection close', undef) for @{delete $self->{waiting} || []};
}

sub _next {
  my $self = shift;

  return unless my $next = $self->{waiting}[0];
  return if $next->{sth};

  my $dbh  = $self->dbh;
  my $flag = lc $dbh->{Driver}{Name} eq 'mariadb' ? 'mariadb_async' : 'async';
  my $sth  = $next->{sth} = $self->dbh->prepare($next->{query}, {$flag => 1});
  _bind_params($sth, @{$next->{args}});
  $sth->execute;
}

sub _unwatch {
  Mojo::IOLoop->singleton->reactor->remove(delete $_[0]->{handle}) if $_[0]->{handle};
}

sub _watch {
  my $self = shift;
  return if $self->{handle};

  my $dbh           = $self->dbh;
  my $driver        = lc $dbh->{Driver}{Name};
  my $ready_method  = "${driver}_async_ready";
  my $result_method = "${driver}_async_result";
  my $fd            = $driver eq 'mariadb' ? $dbh->mariadb_sockfd : $dbh->mysql_fd;
  open $self->{handle}, '<&', $fd or die "Could not dup $driver fd: $!";
  Mojo::IOLoop->singleton->reactor->io(
    $self->{handle} => sub {
      return unless my $waiting = $self->{waiting};
      return unless @$waiting and $waiting->[0]{sth} and $waiting->[0]{sth}->$ready_method;
      my ($cb, $err, $sth) = @{shift @$waiting}{qw(cb err sth)};

      # Do not raise exceptions inside the event loop
      my $rv  = do { local $sth->{RaiseError} = 0; $sth->$result_method };
      my $res = $self->results_class->new(db => $self, sth => $sth);

      $err = undef if defined $rv;
      $err =~ s!\b__MSG__\b!{$dbh->errstr}!e if defined $err;
      $res->{affected_rows} = defined $rv && $rv >= 0 ? 0 + $rv : undef;

      $self->$cb($err, $res);
      $self->_next;
      $self->_unwatch unless $self->backlog;
    }
  )->watch($self->{handle}, 1, 0);
}

1;

=encoding utf8

=head1 NAME

Mojo::mysql::Database - Database

=head1 SYNOPSIS

  use Mojo::mysql::Database;

  my $db = Mojo::mysql::Database->new(mysql => $mysql, dbh => $dbh);

=head1 DESCRIPTION

L<Mojo::mysql::Database> is a container for database handles used by L<Mojo::mysql>.

=head1 ATTRIBUTES

L<Mojo::mysql::Database> implements the following attributes.

=head2 dbh

  my $dbh = $db->dbh;
  $db     = $db->dbh(DBI->new);

Database handle used for all queries.

=head2 mysql

  my $mysql = $db->mysql;
  $db       = $db->mysql(Mojo::mysql->new);

L<Mojo::mysql> object this database belongs to.

=head2 results_class

  $class = $db->results_class;
  $db    = $db->results_class("MyApp::Results");

Class to be used by L</"query">, defaults to L<Mojo::mysql::Results>. Note that
this class needs to have already been loaded before L</"query"> is called.

=head1 METHODS

L<Mojo::mysql::Database> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 backlog

  my $num = $db->backlog;

Number of waiting non-blocking queries.

=head2 begin

  my $tx = $db->begin;

Begin transaction and return L<Mojo::mysql::Transaction> object, which will
automatically roll back the transaction unless
L<Mojo::mysql::Transaction/"commit"> bas been called before it is destroyed.

  # Add names in a transaction
  eval {
    my $tx = $db->begin;
    $db->query('insert into names values (?)', 'Baerbel');
    $db->query('insert into names values (?)', 'Wolfgang');
    $tx->commit;
  };
  say $@ if $@;

=head2 delete

  my $results = $db->delete($table, \%where);

Generate a C<DELETE> statement with L<Mojo::mysql/"abstract"> (usually an
L<SQL::Abstract> object) and execute it with L</"query">. You can also append a
callback to perform operations non-blocking.

  $db->delete(some_table => sub {
    my ($db, $err, $results) = @_;
    ...
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 delete_p

  my $promise = $db->delete_p($table, \%where, \%options);

  Same as L</"delete">, but performs all operations non-blocking and returns a
  L<Mojo::Promise> object instead of accepting a callback.

  $db->delete_p('some_table')->then(sub {
    my $results = shift;
    ...
  })->catch(sub {
    my $err = shift;
    ...
  })->wait;

=head2 disconnect

  $db->disconnect;

Disconnect database handle and prevent it from getting cached again.

=head2 insert

  my $results = $db->insert($table, \@values || \%fieldvals, \%options);

Generate an C<INSERT> statement with L<Mojo::mysql/"abstract"> (usually an
L<SQL::Abstract> object) and execute it with L</"query">. You can also append a
callback to perform operations non-blocking.

  $db->insert(some_table => {foo => 'bar'} => sub {
    my ($db, $err, $results) = @_;
    ...
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 insert_p

  my $promise = $db->insert_p($table, \@values || \%fieldvals, \%options);

Same as L</"insert">, but performs all operations non-blocking and returns a
L<Mojo::Promise> object instead of accepting a callback.

  $db->insert_p(some_table => {foo => 'bar'})->then(sub {
    my $results = shift;
    ...
  })->catch(sub {
    my $err = shift;
    ...
  })->wait;

=head2 pid

  my $pid = $db->pid;

Return the connection id of the backend server process.

=head2 ping

  my $bool = $db->ping;

Check database connection.

=head2 query

  my $results = $db->query('select * from foo');
  my $results = $db->query('insert into foo values (?, ?, ?)', @values);
  my $results = $db->query('insert into foo values (?)', {json => {bar => 'baz'}});
  my $results = $db->query('insert into foo values (?)', {type => SQL_INTEGER, value => 42});

Execute a blocking statement and return a L<Mojo::mysql::Results> object with the
results. You can also append a callback to perform operation non-blocking.

  $db->query('select * from foo' => sub {
    my ($db, $err, $results) = @_;
    ...
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

Hash reference arguments containing a value named C<json>, will be encoded to
JSON text with L<Mojo::JSON/"to_json">. To accomplish the reverse, you can use
the method L<Mojo::mysql::Results/"expand">, which automatically decodes data back
to Perl data structures.

  $db->query('insert into foo values (x) values (?)', {json => {bar => 'baz'}});
  $db->query('select * from foo')->expand->hash->{x}{bar}; # baz

Hash reference arguments containing values named C<type> and C<value> can be
used to bind specific L<DBI> data types (see L<DBI/"DBI Constants">) to
placeholders. This is needed to pass binary data in parameters; see
L<DBD::mysql/"mysql_enable_utf8"> for more information.

  # Insert binary data
  use DBI ':sql_types';
  $db->query('insert into bar values (?)', {type => SQL_BLOB, value => $bytes});

=head2 query_p

  my $promise = $db->query_p('select * from foo');

Same as L</"query">, but performs all operations non-blocking and returns a
L<Mojo::Promise> object instead of accepting a callback.

  $db->query_p('insert into foo values (?, ?, ?)' => @values)->then(sub {
    my $results = shift;
    ...
  })->catch(sub {
    my $err = shift;
    ...
  })->wait;

=head2 quote

  my $escaped = $db->quote($str);

Quote a string literal for use as a literal value in an SQL statement.

=head2 quote_id

  my $escaped = $db->quote_id($id);

Quote an identifier (table name etc.) for use in an SQL statement.

=head2 select

  my $results = $db->select($source, $fields, $where, $order);

Generate a C<SELECT> statement with L<Mojo::mysql/"abstract"> (usually an
L<SQL::Abstract> object) and execute it with L</"query">. You can also append a
callback to perform operations non-blocking.

  $db->select(some_table => ['foo'] => sub {
    my ($db, $err, $results) = @_;
    ...
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 select_p

  my $promise = $db->select_p($source, $fields, $where, $order);

Same as L</"select">, but performs all operations non-blocking and returns a
L<Mojo::Promise> object instead of accepting a callback.

  $db->select_p(some_table => ['foo'] => {bar => 'yada'})->then(sub {
    my $results = shift;
    ...
  })->catch(sub {
    my $err = shift;
    ...
  })->wait;

=head2 update

  my $results = $db->update($table, \%fieldvals, \%where);

Generate an C<UPDATE> statement with L<Mojo::mysql/"abstract"> (usually an
L<SQL::Abstract> object) and execute it with L</"query">. You can also append a
callback to perform operations non-blocking.

  $db->update(some_table => {foo => 'baz'} => {foo => 'bar'} => sub {
    my ($db, $err, $results) = @_;
    ...
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 update_p

  my $promise = $db->update_p($table, \%fieldvals, \%where, \%options);

Same as L</"update">, but performs all operations non-blocking and returns a
L<Mojo::Promise> object instead of accepting a callback.

  $db->update_p(some_table => {foo => 'baz'} => {foo => 'bar'})->then(sub {
    my $results = shift;
    ...
  })->catch(sub {
    my $err = shift;
    ...
  })->wait;

=head2 tables

  my $tables = $db->tables;

Return an array reference with table names for this database.

=head1 SEE ALSO

L<Mojo::mysql>.

=cut
