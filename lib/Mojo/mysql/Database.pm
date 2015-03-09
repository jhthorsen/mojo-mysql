package Mojo::mysql::Database;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Mojo::Util 'deprecated';

has 'mysql';

sub backlog { croak 'Method "backlog" not implemented by subclass' }

sub begin {croak 'Method "begin" not implemented by subclass' }

sub disconnect { croak 'Method "disconnect" not implemented by subclass' }

# DEPRECATED!
sub do {
  deprecated 'Mojo::mysql::Database::do is DEPRECATED'
    . ' in favor of Mojo::mysql::Database::query';
  my $self = shift;
  $self->query(@_);
  return $self;
}

sub pid { croak 'Method "pid" not implemented by subclass' }

sub ping { croak 'Method "ping" not implemented by subclass' }

sub query { croak 'Method "query" not implemented by subclass' }

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
