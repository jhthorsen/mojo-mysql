package Mojo::mysql::Database;
use Mojo::Base -base;

use Mojo::mysql::Results;
use Mojo::mysql::Transaction;
use Mojo::mysql::Util 'expand_sql';
use Scalar::Util 'weaken';
use Carp 'croak';

has [qw(connection mysql)];

sub DESTROY {
  my $self = shift;
  return unless my $c = $self->connection;
  return unless my $mysql = $self->mysql;
  $mysql->_enqueue($c);
}

sub backlog { scalar @{shift->{waiting} || []} }

sub begin {
  my $self = shift;
  $self->do('START TRANSACTION');
  my $tx = Mojo::mysql::Transaction->new(db => $self);
  weaken $tx->{db};
  return $tx;
}

sub disconnect { shift->connection->disconnect }

sub pid { shift->connection->{connection_id} }

sub ping { shift->connection->ping }

sub do {
    my $self = shift;
    my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
    my $sql = expand_sql(@_);

    croak 'async query in flight' if $self->backlog and !$cb;
    $self->_subscribe unless $self->backlog;

    push @{$self->{waiting}}, { cb => $cb, sql => $sql, started => 0};

    # Blocking
    unless ($cb) {
        $self->connection->query($sql);
        $self->_unsubscribe;
        my $current = shift @{$self->{waiting}};
        croak $self->connection->{error_message} if $self->connection->{error_code};
        return $self;
    }

    # Non-blocking
    $self->_next;
    return $self;
}

sub query {
  my $self = shift;
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  my $sql = expand_sql(@_);

  croak 'async query in flight' if $self->backlog and !$cb;
  $self->_subscribe unless $self->backlog;

  push @{$self->{waiting}}, { cb => $cb, sql => $sql, results => Mojo::mysql::Results->new, count => 0, started => 0};

  # Blocking
  unless ($cb) {
    $self->connection->query($sql);
    $self->_unsubscribe;
    my $current = shift @{$self->{waiting}};
    croak $self->connection->{error_message} if $self->connection->{error_code};
    return $current->{results};
  }

  # Non-blocking
  $self->_next;
}

sub _next {
  my $self = shift;

  return unless my $next = $self->{waiting}[0];
  return if $next->{started}++;

  $self->connection->query($next->{sql}, sub { 
    my $c = shift;
    my $current = shift @{$self->{waiting}};
    my $error = $c->{error_message};

    $self->backlog ? $self->_next : $self->_unsubscribe;

    my $cb = $current->{cb};
    $self->$cb($error, $current->{results});
  });

}

sub _subscribe {
  my $self = shift;

  $self->connection->on(fields => sub {
    my ($c, $fields) = @_;
    return unless my $res = $self->{waiting}->[0]->{results};
    push @{ $res->{_columns} }, $fields;
    $self->{waiting}->[0]->{count}++;
  });

  $self->connection->on(result => sub {
    my ($c, $row) = @_;
    return unless my $res = $self->{waiting}->[0]->{results};
    push @{ $res->{_results}->[$self->{waiting}->[0]->{count} - 1] //= [] }, $row;
  });

  $self->connection->on(end => sub {
    my $c = shift;
    return unless my $res = $self->{waiting}->[0]->{results};
    $res->{$_} = $c->{$_} for qw(affected_rows last_insert_id warnings_count);
  });

  $self->connection->on(errors => sub {
    my $c = shift;
    return unless my $res = $self->{waiting}->[0]->{results};
    $res->{$_} = $c->{$_} for qw(error_code sql_state error_message);
  });
}

sub _unsubscribe {
  my $self = shift;
  $self->connection->unsubscribe($_) for qw(fields result end errors);
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

=head2 connection

  my $c = $db->connection;
  $db   = $db->connection(Mojo::mysql::Connection->new);

L<Mojo::mysql::Connection> object used for all queries.

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

  my $tx = $db->begin;
  $db->query('insert into names values (?)', 'Baerbel');
  $db->query('insert into names values (?)', 'Wolfgang');
  $tx->commit;

=head2 disconnect

  $db->disconnect;

Disconnect database handle and prevent it from getting cached again.

=head2 do

  $db = $db->do('create table foo (bar text)');

Execute a statement and discard its result.

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

=head1 SEE ALSO

L<Mojo::mysql>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
