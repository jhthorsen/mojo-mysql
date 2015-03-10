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
    $db->connect($self->url, $self->options);
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
  $mysql->db->do('create table if not exists names (name text)');

  # Insert a few rows
  my $db = $mysql->db;
  $db->query('insert into names values (?)', 'Sara');
  $db->query('insert into names values (?)', 'Daniel');

  # Select all rows blocking
  say for $db->query('select * from names')
    ->hashes->map(sub { $_->{name} })->each;

  # Select all rows non-blocking
  Mojo::IOLoop->delay(
    sub {
      my $delay = shift;
      $db->query('select * from names' => $delay->begin);
    },
    sub {
      my ($delay, $err, $results) = @_;
      say for $results->hashes->map(sub { $_->{name} })->each;
    }
  )->wait;

=head1 DESCRIPTION

L<Mojo::mysql> is a tiny wrapper around L<DBD::mysql> that makes
L<MySQL|http://www.mysql.org> a lot of fun to use with the
L<Mojolicious|http://mojolicio.us> real-time web framework.

Database handles are cached automatically, so they can be reused
transparently to increase performance. While all I/O operations are performed
blocking, you can wait for long running queries asynchronously, allowing the
L<Mojo::IOLoop> event loop to perform other tasks in the meantime. Since
database connections usually have a very low latency, this often results in
very good performance.

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

MySQL does not support DDL transactions. B<Therefore, migrations should be used with extreme caution. Backup your database. You've been warned.> 

  my $migrations = $mysql->migrations;
  $mysql         = $mysql->migrations(Mojo::mysql::Migrations->new);

L<Mojo::mysql::Migrations> object you can use to change your database schema more
easily.

  # Load migrations from file and migrate to latest version
  $mysql->migrations->from_file('/Users/sri/migrations.sql')->migrate;

=head2 options

  my $options = $mysql->options;
  $mysql      = $mysql->options({mysql_use_result => 1});

Options for database handles, defaults to activating C<mysql_enable_utf8>, C<AutoCommit> as well as
C<RaiseError> and deactivating C<PrintError>.

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

L<Mojo::Pg>, L<https://github.com/jhthorsen/mojo-mysql>,
L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
