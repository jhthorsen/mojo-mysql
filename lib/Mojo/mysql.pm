package Mojo::mysql;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use DBI;
use Mojo::mysql::Database;
use Mojo::mysql::Migrations;
use Mojo::URL;
use Scalar::Util 'weaken';

has dsn             => 'dbi:mysql:dbname=test';
has max_connections => 5;
has migrations      => sub {
  my $migrations = Mojo::mysql::Migrations->new(mysql => shift);
  weaken $migrations->{mysql};
  return $migrations;
};
has options => sub {
  {
    mysql_enable_utf8 => 1,
    AutoCommit => 1,
    AutoInactiveDestroy => 1,
    PrintError => 0,
    RaiseError => 1
  }
};
has [qw(password username)] => '';

our $VERSION = '0.09';

sub db {
  my $self = shift;

  # Fork safety
  delete @$self{qw(pid queue)} unless ($self->{pid} //= $$) eq $$;

  my ($dbh, $handle) = @{$self->_dequeue};
  return Mojo::mysql::Database->new(dbh => $dbh, handle => $handle, mysql => $self);
}

sub from_string {
  my ($self, $str) = @_;

  # Protocol
  return $self unless $str;
  my $url = Mojo::URL->new($str);
  croak qq{Invalid MySQL connection string "$str"} unless $url->protocol eq 'mysql';

  # Database
  my $dsn = 'dbi:mysql:dbname=' . $url->path->parts->[0];

  # Host and port
  if (my $host = $url->host) { $dsn .= ";host=$host" }
  if (my $port = $url->port) { $dsn .= ";port=$port" }

  # Username and password
  if (($url->userinfo // '') =~ /^([^:]+)(?::([^:]+))?$/) {
    $self->username($1);
    $self->password($2) if defined $2;
  }

  # Options
  my $hash = $url->query->to_hash;
  @{$self->options}{keys %$hash} = values %$hash;

  return $self->dsn($dsn);
}

sub new { @_ > 1 ? shift->SUPER::new->from_string(@_) : shift->SUPER::new }

sub _dequeue {
  my $self = shift;
  my $dbh;

  while (my $c = shift @{$self->{queue} || []}) { return $c if $c->[0]->ping }
  $dbh = DBI->connect(map { $self->$_ } qw(dsn username password options));

  # <mst> batman's probably going to have more "fun" than you have ...
  # especially once he discovers that DBD::mysql randomly reconnects under
  # you, silently, but only if certain env vars are set
  # hint: force-set mysql_auto_reconnect or whatever it's called to 0
  $dbh->{mysql_auto_reconnect} = 0;
  # Maintain Commits with Mojo::mysql::Transaction
  $dbh->{AutoCommit} = 1;

  $self->emit(connection => $dbh);
  [$dbh];
}

sub _enqueue {
  my ($self, $dbh, $handle) = @_;
  my $queue = $self->{queue} ||= [];
  push @$queue, [$dbh, $handle] if $dbh->{Active};
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
  $mysql->db->query(
    'create table names (id integer auto_increment primary key, name text)');

  # Insert a few rows
  my $db = $mysql->db;
  $db->query('insert into names (name) values (?)', 'Sara');
  $db->query('insert into names (name) values (?)', 'Stefan');

  # Insert more rows in a transaction
  eval {
    my $tx = $db->begin;
    $db->query('insert into names (name) values (?)', 'Baerbel');
    $db->query('insert into names (name) values (?)', 'Wolfgang');
    $tx->commit;
  };
  say $@ if $@;

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

  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head1 DESCRIPTION

L<Mojo::mysql> is a tiny wrapper around L<DBD::mysql> that makes
L<MySQL|http://www.mysql.org> a lot of fun to use with the
L<Mojolicious|http://mojolicio.us> real-time web framework.

Database and handles are cached automatically, so they can be reused
transparently to increase performance. And you can handle connection timeouts
gracefully by holding on to them only for short amounts of time.

  use Mojolicious::Lite;
  use Mojo::mysql;

  helper mysql =>
    sub { state $pg = Mojo::mysql->new('mysql://sri:s3cret@localhost/db') };

  get '/' => sub {
    my $c  = shift;
    my $db = $c->mysql->db;
    $c->render(json => $db->query('select now() as time')->hash);
  };

  app->start;

While all I/O operations are performed blocking, you can wait for long running
queries asynchronously, allowing the L<Mojo::IOLoop> event loop to perform
other tasks in the meantime. Since database connections usually have a very low
latency, this often results in very good performance.

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

  my $migrations = $mysql->migrations;
  $mysql         = $mysql->migrations(Mojo::mysql::Migrations->new);

L<Mojo::mysql::Migrations> object you can use to change your database schema more
easily.

  # Load migrations from file and migrate to latest version
  $mysql->migrations->from_file('/Users/sri/migrations.sql')->migrate;

MySQL does not support nested transactions and DDL transactions.
DDL statements cause implicit C<COMMIT>. C<ROLLBACK> will be called if
any step of migration script fails, but only DML statements can be reverted.

This means database can be left in unknown state if migration script fails.
Use this feature with caution and remember to always backup your database.

=head2 options

  my $options = $mysql->options;
  $mysql      = $mysql->options({mysql_use_result => 1});

Options for database handles, defaults to activating C<mysql_enable_utf8>, C<AutoCommit>,
C<AutoInactiveDestroy> as well as C<RaiseError> and deactivating C<PrintError>.
Note that C<AutoCommit> and C<RaiseError> are considered mandatory, so
deactivating them would be very dangerous.

C<mysql_auto_reconnect> is never enabled, L<Mojo::mysql> takes care of dead connections.

C<AutoCommit> cannot not be disabled, use $db->L<begin|Mojo::mysql::Database/"begin"> to manage transactions.

C<RaiseError> is enabled for blocking and disabled in event loop for non-blocking queries.

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

L<https://github.com/jhthorsen/mojo-mysql>,

L<Mojo::Pg> Async Connector for PostgreSQL using L<DBD::Pg>, L<https://github.com/kraih/mojo-pg>,

L<Mojo::MySQL5> Pure-Perl non-blocking I/O MySQL Connector, L<https://github.com/harry-bix/mojo-mysql5>,

L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
