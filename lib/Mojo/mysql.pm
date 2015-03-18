package Mojo::mysql;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Mojo::Loader 'load_class';
use Mojo::mysql::Migrations;
use Mojo::mysql::Util 'parse_url';
use Scalar::Util 'weaken';

has url             => 'mysql:///test';
has dsn             => 'dbi:mysql:dbname=test';
has max_connections => 5;
has migrations      => sub {
  my $migrations = Mojo::mysql::Migrations->new(mysql => shift);
  weaken $migrations->{mysql};
  return $migrations;
};
has options => sub { { utf8 => 1, found_rows => 1, PrintError => 0, RaiseError => 1, use_dbi => 1} };
has [qw(password username)] => '';

our $VERSION = '0.07';

sub db {
  my $self = shift;

  # Fork safety
  delete @$self{qw(pid queue)} unless ($self->{pid} //= $$) eq $$;

  my ($dbh, $handle) = @{$self->_dequeue};
  my $db = ($self->options->{use_dbi} // 1) ?
    Mojo::mysql::DBI::Database->new(dbh => $dbh, handle => $handle, mysql => $self) :
    Mojo::mysql::Native::Database->new(connection => $dbh, mysql => $self);

  if (!$dbh) {
    $db->connect(map { $self->$_ } qw(url username password options));
    $self->emit(connection => $db);
  }
  return $db;
}

sub from_string {
  my ($self, $str) = @_;

  my $parts = parse_url($str);
  croak qq{Invalid MySQL connection string "$str"} unless defined $parts;

  # Only for Compatibility
  $self->username($parts->{username}) if exists $parts->{username};
  $self->password($parts->{password}) if exists $parts->{password};
  $self->dsn($parts->{dsn});
  @{$self->options}{keys %{$parts->{options}}} = values %{$parts->{options}};

  load_class(
    ($self->options->{use_dbi} // 1) ? 'Mojo::mysql::DBI::Database' : 'Mojo::mysql::Native::Database');

  return $self->url($str);
}

sub new { @_ > 1 ? shift->SUPER::new->from_string(@_) : shift->SUPER::new }

sub _dequeue {
  my $self = shift;

  while (my $c = shift @{$self->{queue} || []}) { return $c if $c->[0]->ping }
  return [undef, undef];
}

sub _enqueue {
  my ($self, $dbh, $handle) = @_;
  my $queue = $self->{queue} ||= [];
  push @$queue, [$dbh, $handle];
  shift @{$self->{queue}} while @{$self->{queue}} > $self->max_connections;
}

1;

=encoding utf8

=head1 NAME

Mojo::mysql - Mojolicious and Async MySQL

=head1 SYNOPSIS

  use Mojo::mysql;

  # Create a table
  my $mysql = Mojo::mysql->new('mysql://username@/test');
  $mysql->db->query('create table names (id integer auto_increment primary key, name text)');

  # Insert a few rows
  my $db = $mysql->db;
  $db->query('insert into names (name) values (?)', 'Sara');
  $db->query('insert into names (name) values (?)', 'Stefan');

  # Insert more rows in a transaction
  {
    my $tx = $db->begin;
    $db->query('insert into names (name) values (?)', 'Baerbel');
    $db->query('insert into names (name) values (?)', 'Wolfgang');
    $tx->commit;
  };

  # Insert another row and return the generated id
  say $db->query('insert into names (name) values (?)', 'Daniel')
    ->last_insert_id;

  # Select one row at a time
  my $results = $db->query('select * from names');
  while (my $next = $results->hash) {
    say $next->{name};
  }

  # Select all rows blocking
  $db->query('select * from names')
    ->hashes->map(sub { $_->{name} })->join("\n")->say;

  # Select all rows non-blocking
  Mojo::IOLoop->delay(
    sub {
      my $delay = shift;
      $db->query('select * from names' => $delay->begin);
    },
    sub {
      my ($delay, $err, $results) = @_;
      $results->hashes->map(sub { $_->{name} })->join("\n")->say;
    }
  )->wait;

=head1 DESCRIPTION

L<Mojo::mysql> makes L<MySQL|http://www.mysql.org> a lot of fun to use with the
L<Mojolicious|http://mojolicio.us> real-time web framework.

Database handles are cached automatically, so they can be reused transparently
to increase performance. And you can handle connection timeouts gracefully by
holding on to them only for short amounts of time.

  use Mojolicious::Lite;
  use Mojo::mysql;

  helper mysql =>
    sub { state $mysql = Mojo::mysql->new('mysql://sri:s3cret@localhost/db') };

  get '/' => sub {
    my $c  = shift;
    my $db = $c->mysql->db;
    $c->render(json => $db->query('select now() as time')->hash);
  };

  app->start;

This module implements two methods of connecting to MySQL server.

=over 2

=item Using DBI and DBD::mysql

L<DBD::mysql> allows you to submit a long-running query to the server
and have an event loop inform you when it's ready. 

While all I/O operations are performed blocking,
you can wait for long running queries asynchronously, allowing the
L<Mojo::IOLoop> event loop to perform other tasks in the meantime. Since
database connections usually have a very low latency, this often results in
very good performance.

=item Using Native Pure-Perl Non-Blocking I/O

L<Mojo::mysql::Connection> is Fully asynchronous implementation
of MySQL Client Server Protocol managed by L<Mojo::IOLoop>.

This method is EXPERIMENTAL.

=back

Every database connection can only handle one active query at a time, this
includes asynchronous ones. So if you start more than one, they will be put on
a waiting list and performed sequentially. To perform multiple queries
concurrently, you have to use multiple connections.
 
  # Performed sequentially (10 seconds)
  my $db = $mysql->db;
  $db->query('select sleep(5)' => sub {...});
  $db->query('select sleep(5)' => sub {...});
 
  # Performed concurrently (5 seconds)
  $mysql->db->query('select sleep(5)' => sub {...});
  $mysql->db->query('select sleep(5)' => sub {...});
 
All cached database handles will be reset automatically if a new process has
been forked, this allows multiple processes to share the same L<Mojo::mysql>
object safely.


Note that this whole distribution is EXPERIMENTAL and will change without
warning!

=head1 EVENTS

L<Mojo::mysql> inherits all events from L<Mojo::EventEmitter> and can emit the
following new ones.

=head2 connection

  $mysql->on(connection => sub {
    my ($mysql, $dbh) = @_;
    ...
  });

Emitted when a new database connection has been established.

=head1 ATTRIBUTES

L<Mojo::mysql> implements the following attributes.

=head2 url

  my $url = $mysql->url;
  $url  = $mysql->url('mysql://user@host/test');

Connection URL string.

=head2 dsn

  my $dsn = $mysql->dsn;
  $mysql  = $mysql->dsn('dbi:mysql:dbname=foo');

Data Source Name, defaults to C<dbi:mysql:dbname=test>.

=head2 max_connections

  my $max = $mysql->max_connections;
  $mysql  = $mysql->max_connections(3);

Maximum number of idle database handles to cache for future use, defaults to
C<5>.

=head2 migrations

MySQL does not support nested transactions and DDL transactions. DDL statements cause implicit C<COMMIT>.
B<Therefore, migrations should be used with extreme caution.
Backup your database. You've been warned.> 

  my $migrations = $mysql->migrations;
  $mysql         = $mysql->migrations(Mojo::mysql::Migrations->new);

L<Mojo::mysql::Migrations> object you can use to change your database schema more
easily.

  # Load migrations from file and migrate to latest version
  $mysql->migrations->from_file('/Users/sri/migrations.sql')->migrate;

=head2 options

  my $options = $mysql->options;
  $mysql      = $mysql->options({found_rows => 0, RaiseError => 1});

Options for connecting to server.

Supported Options are:

=over 2

=item use_dbi

Use L<DBI|DBI> and L<DBD::mysql> when enabled or Native implementation when disabled.

=item found_rows

Enables or disables the flag C<CLIENT_FOUND_ROWS> while connecting to the server.
Without C<found_rows>, if you perform a query like
 
  UPDATE $table SET id = 1 WHERE id = 1;
 
then the MySQL engine will return 0, because no rows have changed.
With C<found_rows>, it will return the number of rows that have an id 1.

=item multi_statements

Enables or disables the flag C<CLIENT_MULTI_STATEMENTS> while connecting to the server.
If enabled multiple statements separated by semicolon (;) can be send with single
call to $db->L<query|Mojo::mysql::Database/query>.

=item utf8

Set default character set to C<utf-8> while connecting to the server
and decode correctly utf-8 text results.

=item connect_timeout

The connect request to the server will timeout if it has not been successful
after the given number of seconds.

=item query_timeout

If enabled, the read or write operation to the server will timeout
if it has not been successful after the given number of seconds.

=item PrintError

C<warn> on errors.

=item RaiseError

C<die> on error in blocking operations.

=back

Default Options are:

C<use_dbi = 1>,
C<utf8 = 1>,
C<found_rows = 1>,
C<PrintError = 0>,
C<RaiseError = 1>

When using DBI method, driver private options (prefixed with C<mysql_> of L<DBD::mysql> are supported.

C<mysql_auto_reconnect> is never enabled, L<Mojo::mysql> takes care of dead connections.

C<AutoCommit> cannot not be disabled, use $db->L<begin|Mojo::mysql::Database/begin> to manage transactions.

C<RaiseError> is disabled in event loop for asyncronous queries.

=head2 password

  my $password = $mysql->password;
  $mysql       = $mysql->password('s3cret');

Database password, defaults to an empty string.

=head2 username

  my $username = $mysql->username;
  $mysql       = $mysql->username('batman');

Database username, defaults to an empty string.

=head1 METHODS

L<Mojo::mysql> inherits all methods from L<Mojo::EventEmitter> and implements the
following new ones.

=head2 db

  my $db = $mysql->db;

Get L<Mojo::mysql::Database> object for a cached or newly created database
handle. The database handle will be automatically cached again when that
object is destroyed, so you can handle connection timeouts gracefully by
holding on to it only for short amounts of time.

  # Add up all the money
  say $mysql->db->query('select * from accounts')
    ->hashes->reduce(sub { $a->{money} + $b->{money} });

=head2 from_string

  $mysql = $mysql->from_string('mysql://user@/test');

Parse configuration from connection string.

  # Just a database
  $mysql->from_string('mysql:///db1');

  # Username and database
  $mysql->from_string('mysql://batman@/db2');

  # Username, password, host and database
  $mysql->from_string('mysql://batman:s3cret@localhost/db3');

  # Username, domain socket and database
  $mysql->from_string('mysql://batman@%2ftmp%2fmysql.sock/db4');

  # Username, database and additional options
  $mysql->from_string('mysql://batman@/db5?PrintError=1&RaiseError=0');

=head2 new

  my $mysql = Mojo::mysql->new;
  my $mysql = Mojo::mysql->new('mysql://user@/test');

Construct a new L<Mojo::mysql> object and parse connection string with
L</"from_string"> if necessary.

=head1 REFERENCE

This is the class hierarchy of the L<Mojo::mysql> distribution.

=over 2

=item * L<Mojo::mysql>

=item * L<Mojo::mysql::Database>

=item * L<Mojo::mysql::Migrations>

=item * L<Mojo::mysql::Results>

=item * L<Mojo::mysql::Transaction>

=item * L<Mojo::mysql::Connection>

=item * L<Mojo::mysql::Native::Database>

=item * L<Mojo::mysql::Native::Results>

=item * L<Mojo::mysql::Native::Transaction>

=item * L<Mojo::mysql::DBI::Database>

=item * L<Mojo::mysql::DBI::Results>

=item * L<Mojo::mysql::DBI::Transaction>

=back

=head1 AUTHOR

Curt Hochwender, C<hochwender@centurytel.net>.

Jan Henning Thorsen, C<jhthorsen@cpan.org>.

This code is mostly a rip-off from Sebastian Riedel's L<Mojo::Pg>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014-2015, Jan Henning Thorsen.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojo::Pg>, L<https://github.com/jhthorsen/mojo-mysql>,
L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
