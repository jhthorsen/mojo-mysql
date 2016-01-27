package Mojo::mysql::Database;
use Mojo::Base 'Mojo::EventEmitter';

use DBD::mysql;
use Mojo::IOLoop;
use Mojo::mysql::Results;
use Mojo::mysql::Transaction;
use Scalar::Util 'weaken';

has [qw(dbh mysql)];

sub DESTROY {
  my $self = shift;
  my $waiting = $self->{waiting} || [];
  $_->{cb}($self, 'Premature connection close', undef) for @$waiting;
  return unless (my $mysql = $self->mysql) && (my $dbh = $self->dbh);
  $mysql->_enqueue($dbh, $self->{handle});
}

sub backlog { scalar @{shift->{waiting} || []} }

sub begin {
  my $self = shift;
  my $tx = Mojo::mysql::Transaction->new(db => $self);
  weaken $tx->{db};
  return $tx;
}

sub disconnect {
  my $self = shift;
  $_->finish for @{$self->{async_sth} || []};
  $self->_unwatch;
  $self->dbh->disconnect;
}

sub pid { shift->dbh->{mysql_thread_id} }

sub ping { shift->dbh->ping }

sub query {
  my ($self, $query) = (shift, shift);
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;

  # Blocking
  unless ($cb) {
    my $sth = $self->dbh->prepare_cached($query);
    my $rv  = $sth->execute(@_);
    my $res = Mojo::mysql::Results->new(sth => $sth);
    $res->{affected_rows} = defined $rv && $rv >= 0 ? 0 + $rv : undef;
    return $res;
  }

  # Non-blocking
  push @{$self->{waiting}}, {args => [@_], cb => $cb, query => $query};
  $self->$_ for qw(_next _watch);
}

sub quote { shift->dbh->quote(shift) }

sub quote_id { shift->dbh->quote_identifier(shift) }

sub _next {
  my $self = shift;

  return unless my $next = $self->{waiting}[0];
  return if $next->{sth};

  my $sth = $next->{sth} = $self->dbh->prepare_cached($next->{query}, {async => 1});
  $sth->execute(@{$next->{args}});

  # keep reference to async handles to prevent being finished on result destroy while whatching fd
  push @{$self->{async_sth} ||= []}, $sth;
}

sub _unwatch {
  my $self = shift;
  return unless delete $self->{watching};
  Mojo::IOLoop->singleton->reactor->remove($self->{handle});
  $self->{async_sth} = [];
}

sub _watch {
  my $self = shift;

  return if $self->{watching} || $self->{watching}++;

  my $dbh = $self->dbh;
  $self->{handle} ||= do {
    open my $FH, '<&', $dbh->mysql_fd or die "Dup mysql_fd: $!";
    $FH;
  };
  Mojo::IOLoop->singleton->reactor->io(
    $self->{handle} => sub {
      my $reactor = shift;

      return unless my $waiting = $self->{waiting};
      return unless @$waiting and $waiting->[0]{sth} and $waiting->[0]{sth}->mysql_async_ready;
      my ($sth, $cb) = @{shift @$waiting}{qw(sth cb)};

      # Do not raise exceptions inside the event loop
      my $rv = do { local $sth->{RaiseError} = 0; $sth->mysql_async_result; };
      my $err = defined $rv ? undef : $dbh->errstr;
      my $res = Mojo::mysql::Results->new(sth => $sth);
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

L<Mojo::mysql::Database> is a container for database handles used by L<Mojo::MySQL>.

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

=head2 disconnect

  $db->disconnect;

Disconnect database handle and prevent it from getting cached again.

=head2 pid

  my $pid = $db->pid;

Return the connection id of the backend server process.

=head2 ping

  my $bool = $db->ping;

Check database connection.

=head2 query

  my $results = $db->query('select * from foo');
  my $results = $db->query('insert into foo values (?, ?, ?)', @values);

Execute a blocking statement and return a L<Mojo::mysql::Results> object with the
results. You can also append a callback to perform operation non-blocking.

  $db->query('select * from foo' => sub {
    my ($db, $err, $results) = @_;
    ...
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 quote

  my $escaped = $db->quote($str);
 
Quote a string literal for use as a literal value in an SQL statement.
 
=head2 quote_id
 
  my $escaped = $db->quote_id($id);
 
Quote an identifier (table name etc.) for use in an SQL statement.

=head1 SEE ALSO

L<Mojo::mysql>.

=cut
