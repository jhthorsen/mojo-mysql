package Mojo::mysql::DBI::Database;
use Mojo::Base 'Mojo::mysql::Database';

use DBI;
use Mojo::IOLoop;
use Mojo::mysql::DBI::Results;
use Mojo::mysql::DBI::Transaction;
use Mojo::mysql::Util 'parse_url';
use Scalar::Util 'weaken';
use Carp 'croak';

our %dbi_options = (
  mysql_client_found_rows => 'found_rows',
  mysql_enable_utf8 => 'utf8',
  mysql_multi_statements => 'multi_statements',
  mysql_connect_timeout => 'connect_timeout',
  mysql_read_timeout => 'query_timeout',
  mysql_write_timeout => 'query_timeout',
);

has 'dbh';

sub DESTROY {
  my $self = shift;
  return unless my $dbh   = $self->dbh;
  return unless my $mysql = $self->mysql;
  $mysql->_enqueue($dbh, $self->{handle}) if $dbh->{Active};
}

sub backlog { scalar @{shift->{waiting} || []} }

sub begin {
  my $self = shift;
  $self->dbh->begin_work;
  my $tx = Mojo::mysql::DBI::Transaction->new(db => $self);
  weaken $tx->{db};
  return $tx;
}

sub connect {
  my ($self, $url, $options) = @_;
  my $parts = parse_url($url);
  croak "Invalid URL '$url'" unless defined $parts;
  my %connect_options = map { $_ => $options->{$_} }
    grep { $_ =~ /^mysql_/ or $_ eq 'PrintError' } keys %$options;

  foreach (keys %dbi_options) {
    $connect_options{$_} = $options->{$dbi_options{$_}}
      if !exists $connect_options{$_} and exists $options->{$dbi_options{$_}};
  }

  $connect_options{AutoCommit} = 1;
  $connect_options{RaiseError} = 1;
  $connect_options{mysql_auto_reconnect} = 0;

  my $dbh = DBI->connect($parts->{dsn}, $parts->{username}, $parts->{password}, \%connect_options);
  return $self->dbh($dbh);
}

sub disconnect {
  my $self = shift;
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
    my $sth = $self->dbh->prepare($query);
    my $rv = $sth->execute(@_);
    my $res = Mojo::mysql::DBI::Results->new(sth => $sth);
    $res->{affected_rows} = defined $rv && $rv >= 0 ? 0 + $rv : undef;
    return $res;
  }

  # Non-blocking
  push @{$self->{waiting}}, {args => [@_], cb => $cb, query => $query};
  $self->$_ for qw(_next _watch);
}

sub _next {
  my $self = shift;

  return unless my $next = $self->{waiting}[0];
  return if $next->{sth};

  my $sth = $next->{sth} = $self->dbh->prepare($next->{query}, {async => 1});
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
      my $res = Mojo::mysql::DBI::Results->new(sth => $sth);
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

Mojo::mysql::DBI::Database - DBD::mysql Database

=head1 SYNOPSIS

  use Mojo::mysql::DBI::Database;

  my $db = Mojo::mysql::DBI::Database->new(mysql => $mysql, dbh => $dbh);

=head1 DESCRIPTION

L<Mojo::mysql::DBI::Database> is a container for L<DBI> database handles used by L<Mojo::mysql>.
L<Mojo::mysql::DBI::Database> is based on L<Mojo::mysql::Database>.

=head1 ATTRIBUTES

L<Mojo::mysql::DBI::Database> implements the following attributes.

=head2 dbh

  my $dbh = $db->dbh;
  $db     = $db->dbh(DBI->new);

Database handle used for all queries.

=head2 mysql

L<Mojo::mysql> object this database belongs to.

=head1 METHODS

L<Mojo::mysql::DBI::Database> inherits all methods from L<Mojo::mysql::Database> and
implements the following ones.

=head2 backlog

  my $num = $db->backlog;

Number of waiting non-blocking queries.

=head2 begin

  my $tx = $db->begin;

Begin transaction and return L<Mojo::mysql::DBI::Transaction> object, which will
automatically roll back the transaction unless
L<Mojo::mysql::DBI::Transaction/"commit"> bas been called before it is destroyed.

  my $tx = $db->begin;
  $db->query('insert into names values (?)', 'Baerbel');
  $db->query('insert into names values (?)', 'Wolfgang');
  $tx->commit;

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

Execute a blocking statement and return a L<Mojo::mysql::DBI::Results> object with the
results. You can also append a callback to perform operation non-blocking.

  $db->query('select * from foo' => sub {
    my ($db, $err, $results) = @_;
    ...
  });
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head1 SEE ALSO

L<Mojo::mysql::Database>, L<Mojo::mysql>.

=cut
