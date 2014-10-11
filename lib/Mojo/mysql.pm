package Mojo::mysql;
use Mojo::Base -base;

use Carp 'croak';
use DBI;
use Mojo::mysql::Database;
use Mojo::URL;

has dsn             => 'dbi:mysql:dbname=test';
has max_connections => 5;
has options         => sub { {AutoCommit => 1, PrintError => 0, RaiseError => 1} };
has [qw(password username)] => '';

our $VERSION = '0.01';

sub db {
  my $self = shift;

  # Fork safety
  delete @$self{qw(pid queue)} unless ($self->{pid} //= $$) eq $$;

  return Mojo::mysql::Database->new(dbh => $self->_dequeue, mysql => $self);
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
  while (my $dbh = shift @{$self->{queue} || []}) { return $dbh if $dbh->ping }
  return DBI->connect(map { $self->$_ } qw(dsn username password options));
}

sub _enqueue {
  my ($self, $dbh) = @_;
  push @{$self->{queue}}, $dbh if $dbh->{Active};
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
  $mysql->db->do('create table if not exists names (name varchar(255))');

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

Database and statement handles are cached automatically, so they can be reused
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

=head2 options

  my $options = $mysql->options;
  $mysql      = $mysql->options({AutoCommit => 1});

Options for database handles, defaults to activating C<AutoCommit> as well as
C<RaiseError> and deactivating C<PrintError>.

=head2 password

  my $password = $mysql->password;
  $mysql       = $mysql->password('s3cret');

Database password, defaults to an empty string.

=head2 username

  my $username = $mysql->username;
  $mysql       = $mysql->username('batman');

Database username, defaults to an empty string.

=head1 METHODS

L<Mojo::mysql> inherits all methods from L<Mojo::Base> and implements the
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

=head1 AUTHOR

Jan Henning Thorsen, C<jhthorsen@cpan.org>.

This code is mostly a rip-off from Sebastian Riedel's L<Mojo::Pg>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<Mojo::Pg>, L<https://github.com/jhthorsen/mojo-mysql>,
L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
