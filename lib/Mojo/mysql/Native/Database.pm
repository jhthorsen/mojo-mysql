package Mojo::mysql::Native::Database;
use Mojo::Base 'Mojo::mysql::Database';

use Mojo::mysql::Connection;
use Mojo::mysql::Native::Results;
use Mojo::mysql::Native::Transaction;
use Mojo::mysql::Util qw(expand_sql parse_url);
use Scalar::Util 'weaken';
use Carp 'croak';

has 'connection';

sub DESTROY {
  my $self = shift;
  return unless my $c = $self->connection;
  return unless my $mysql = $self->mysql;
  $mysql->_enqueue($c);
}

sub backlog { scalar @{shift->{waiting} || []} }

sub begin {
  my $self = shift;
  $self->query('START TRANSACTION');
  $self->query('SET autocommit=0');
  my $tx = Mojo::mysql::Native::Transaction->new(db => $self);
  weaken $tx->{db};
  return $tx;
}

sub connect {
  my ($self, $url, $options) = @_;
  my $parts = parse_url($url);

  my $c = Mojo::mysql::Connection->new(
    map { $_ => $parts->{$_} } grep { exists $parts->{$_} }
      qw (host port username password database)
  );
  do { $c->options->{$_} = $options->{$_} if exists $options->{$_} }
    for qw(found_rows multi_statements utf8 connect_timeout query_timeout);

  eval { $c->connect };
  croak "Unable to connect to '$url' $@" if $@;
  return $self->connection($c);
}

sub disconnect { shift->connection->disconnect }

sub pid { shift->connection->{connection_id} }

sub ping { shift->connection->ping }

sub query {
  my $self = shift;
  my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
  my $sql = expand_sql(@_);

  croak 'async query in flight' if $self->backlog and !$cb;
  $self->_subscribe unless $self->backlog;

  push @{$self->{waiting}}, { cb => $cb, sql => $sql, count => 0, started => 0,
    results => Mojo::mysql::Native::Results->new };

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
