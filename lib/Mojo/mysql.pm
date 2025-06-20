package Mojo::mysql;
use Mojo::Base 'Mojo::EventEmitter';

use Carp qw(croak);
use DBI;
use File::Spec::Functions qw(file_name_is_absolute);
use Mojo::mysql::Database;
use Mojo::mysql::Migrations;
use Mojo::URL;
use Scalar::Util qw(blessed weaken);
use SQL::Abstract::mysql;

use constant MARIADB => !!eval { require DBD::MariaDB; DBD::MariaDB->VERSION(1.21) };
use constant URI     => !!eval { require URI::db;      URI::db->VERSION(0.10) };

our $VERSION = '1.27';

has abstract        => sub { SQL::Abstract::mysql->new(quote_char => chr(96), name_sep => '.') };
has auto_migrate    => 0;
has database_class  => 'Mojo::mysql::Database';
has dsn             => 'dbi:mysql:dbname=test';
has max_connections => 5;

has migrations => sub {
  my $migrations = Mojo::mysql::Migrations->new(mysql => shift);
  weaken $migrations->{mysql};
  return $migrations;
};

has options => sub {
  my $self    = shift;
  my $options = {AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 1};
  $options->{mysql_enable_utf8} = 1 if $self->dsn =~ m!^dbi:mysql:!;
  return $options;
};

has [qw(password username)] => '';
has pubsub                  => sub {
  require Mojo::mysql::PubSub;
  my $pubsub = Mojo::mysql::PubSub->new(mysql => shift);
  warn "Use of Mojo::mysql::PubSub is highly EXPERIMENTAL and should be considered an experiment"
    unless $ENV{MOJO_PUBSUB_EXPERIMENTAL};
  weaken $pubsub->{mysql};
  return $pubsub;
};

sub close_idle_connections {
  my ($self, $keep) = (shift, $_[0] || 0);
  my $queue = $self->{queue} || [];

  # The database handle needs to be destroyed before the file handle
  shift(@$queue)->[0] = undef while @$queue > $keep;
  return $self;
}

sub db {
  my $self = shift;

  # Fork safety
  delete @$self{qw(pid queue)} unless ($self->{pid} //= $$) eq $$;

  my ($dbh, $handle) = @{$self->_dequeue};
  return $self->database_class->new(dbh => $dbh, handle => $handle, mysql => $self);
}

sub from_string {
  my ($self, $str) = @_;

  # Protocol
  return $self unless $str;
  my $url = blessed $str ? $str : Mojo::URL->new($str);

  my $protocol = $url->can('engine') ? $url->engine : $url->protocol;
  croak qq{Invalid MySQL/MariaDB connection string "$str"} unless $protocol =~ m!^(mariadb|mysql)$!;
  my $dsn = $protocol eq 'mariadb' ? 'dbi:MariaDB' : 'dbi:mysql';

  # Database
  my $dbname = $url->can('dbname') ? $url->dbname : $url->path->parts->[0];
  $dsn .= ":dbname=$dbname" if length $dbname;

  # Host and port
  if (my $host = $url->host) { $dsn .= file_name_is_absolute($host) ? ";mysql_socket=$host" : ";host=$host" }
  if (my $port = $url->port) { $dsn .= ";port=$port" }

  # Need to set the dsn before reading options
  $self->dsn($dsn);

  # Username and password
  if (($url->userinfo // '') =~ /^([^:]+)(?::([^:]+))?$/) {
    $self->username($1);
    $self->password($2) if defined $2;
  }

  # Options
  my $hash = $url->can('query_form_hash') ? $url->query_form_hash : $url->query->to_hash;
  @{$self->options}{keys %$hash} = values %$hash;

  return $self;
}

sub new {
  @_ > 2 || ref $_[-1] eq 'HASH' ? shift->SUPER::new(@_) : shift->SUPER::new->from_string(@_);
}

sub strict_mode {
  my $self = ref $_[0] ? shift : shift->new(@_);
  $self->{strict_mode} = $_[0] ? 1 : @_ ? 0 : 1;
  warn "[Mojo::mysql] strict_mode($self->{strict_mode})\n" if $ENV{DBI_TRACE};
  $self->close_idle_connections;
  return $self;
}

sub _dequeue {
  my $self = shift;
  my ($dsn, $dbh) = ($self->dsn);

  # https://github.com/jhthorsen/mojo-mysql/pull/47
  die "DBD::MariaDB 1.21 is required for Mojo::mysql to work properly" if !MARIADB && index($dsn, 'dbi:MariaDB') == 0;

  while (my $c = shift @{$self->{queue}}) { return $c if $c->[0]->ping }
  $dbh = DBI->connect(map { $self->$_ } qw(dsn username password options));

  # <mst> batman's probably going to have more "fun" than you have ...
  # especially once he discovers that DBD::mysql randomly reconnects under
  # you, silently, but only if certain env vars are set
  # hint: force-set mysql_auto_reconnect or whatever it's called to 0
  Mojo::mysql::Database->_dbh_attr($dbh, mysql_auto_reconnect => 0);

  # Maintain Commits with Mojo::mysql::Transaction
  $dbh->{AutoCommit} = 1;

  $self->_set_strict_mode($dbh) if $self->{strict_mode};
  $self->migrations->migrate    if $self->auto_migrate and !$self->{migrated}++;
  $self->emit(connection => $dbh);
  [$dbh];
}

sub _enqueue {
  my ($self, $dbh, $handle) = @_;
  push @{$self->{queue}}, [$dbh, $handle] if $dbh->{Active};
  $self->close_idle_connections($self->max_connections);
}

sub _set_strict_mode {
  $_[1]->do(q[SET SQL_MODE = CONCAT('ANSI,TRADITIONAL,ONLY_FULL_GROUP_BY,', @@sql_mode)]);
  $_[1]->do(q[SET SQL_AUTO_IS_NULL = 0]);
}

1;

=encoding utf8

=head1 NAME

Mojo::mysql - Mojolicious and Async MySQL/MariaDB

=head1 SYNOPSIS

  use Mojo::mysql;

  # Connect to a local database
  my $mysql = Mojo::mysql->strict_mode('mysql://username@/test');

  # Connect to a remote database
  my $mysql = Mojo::mysql->strict_mode('mysql://username:password@hostname/test');
  # MySQL >= 8.0:
  my $mysql = Mojo::mysql->strict_mode('mysql://username:password@hostname/test;mysql_ssl=1');

  # Use DBD::MariaDB instead of DBD::mysql
  my $mysql = Mojo::mysql->strict_mode('mariadb://username@/test');

  # Create a table
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

  # Use SQL::Abstract::mysql to generate queries for you
  $db->insert('names', {name => 'Isabel'});
  say $db->select('names', undef, {name => 'Isabel'})->hash->{id};
  $db->update('names', {name => 'Bel'}, {name => 'Isabel'});
  $db->delete('names', {name => 'Bel'});

  # Select one row at a time
  my $results = $db->query('select * from names');
  while (my $next = $results->hash) {
    say $next->{name};
  }

  # Select all rows blocking
  $db->query('select * from names')
    ->hashes->map(sub { $_->{name} })->join("\n")->say;

  # Select all rows non-blocking
  $db->query('select * from names' => sub {
    my ($db, $err, $results) = @_;
    $results->hashes->map(sub { $_->{name} })->join("\n")->say;
  });

  # Concurrent non-blocking queries (synchronized with promises)
  my $now   = $db->query_p('select now() as now');
  my $names = $db->query_p('select * from names');
  Mojo::Promise->all($now, $names)->then(sub {
    my ($now, $names) = @_;
    say $now->[0]->hash->{now};
    say $_->{name} for $names->[0]->hashes->each;
  })->catch(sub {
    my $err = shift;
    warn "Something went wrong: $err";
  })->wait;

  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head1 DESCRIPTION

L<Mojo::mysql> is a tiny wrapper around L<DBD::mysql> and L<DBD::MariaDB> that
makes L<MySQL|http://www.mysql.org> and L<MariaDB|https://mariadb.org/> a lot
of fun to use with the L<Mojolicious|http://mojolicio.us> real-time web
framework.

The two DBD drivers are compatible with both MySQL and MariaDB, but they offer
different L</options>. L<DBD::MariaDB> should have better unicode support
though and might become the default in the future.

Database and handles are cached automatically, so they can be reused
transparently to increase performance. And you can handle connection timeouts
gracefully by holding on to them only for short amounts of time.

  use Mojolicious::Lite;
  use Mojo::mysql;

  helper mysql =>
    sub { state $mysql = Mojo::mysql->strict_mode('mysql://sri:s3cret@localhost/db') };

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

=head2 abstract

  $abstract = $mysql->abstract;
  $mysql    = $mysql->abstract(SQL::Abstract::mysql->new);

L<SQL::Abstract::mysql> object used to generate CRUD queries for L<Mojo::mysql::Database>.

  # Generate statements and bind values
  my ($stmt, @bind) = $mysql->abstract->select('names');

=head2 auto_migrate

  my $bool = $mysql->auto_migrate;
  $mysql   = $mysql->auto_migrate($bool);

Automatically migrate to the latest database schema with L</"migrations">, as
soon as the first database connection has been established.

Defaults to false.

=head2 database_class

  $class = $mysql->database_class;
  $mysql = $mysql->database_class("MyApp::Database");

Class to be used by L</"db">, defaults to L<Mojo::mysql::Database>. Note that this
class needs to have already been loaded before L</"db"> is called.

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

MySQL and MariaDB does not support nested transactions and DDL transactions.
DDL statements cause implicit C<COMMIT>. C<ROLLBACK> will be called if any step
of migration script fails, but only DML statements after the last implicit or
explicit C<COMMIT> can be reverted. Not all storage engines (like C<MYISAM>)
support transactions.

This means database will most likely be left in unknown state if migration script fails.
Use this feature with caution and remember to always backup your database.

=head2 options

  my $options = $mysql->options;
  $mysql      = $mysql->options({mysql_use_result => 1});

Options for database handles, defaults to activating C<mysql_enable_utf8> (only
for L<DBD::mysql>), C<AutoCommit>, C<AutoInactiveDestroy> as well as
C<RaiseError> and deactivating C<PrintError>. C<AutoCommit> and C<RaiseError>
are considered mandatory, so deactivating them would be very dangerous.

C<mysql_auto_reconnect> is never enabled, L<Mojo::mysql> takes care of dead connections.

C<AutoCommit> cannot not be disabled, use $db->L<begin|Mojo::mysql::Database/"begin"> to manage transactions.

C<RaiseError> is enabled for blocking and disabled in event loop for non-blocking queries.

About C<mysql_enable_utf8>:

  The mysql_enable_utf8 sets the utf8 charset which only supports up to 3-byte
  UTF-8 encodings. mysql_enable_utf8mb4 (as of DBD::mysql 4.032) properly
  supports encoding unicode characters to up to 4 bytes, such as 𠜎. It means the
  connection charset will be utf8mb4 (supported back to at least mysql 5.5) and
  these unicode characters will be supported, but no other changes.

See also L<https://github.com/jhthorsen/mojo-mysql/pull/32>

=head2 password

  my $password = $mysql->password;
  $mysql       = $mysql->password('s3cret');

Database password, defaults to an empty string.

=head2 pubsub

  my $pubsub = $mysql->pubsub;
  $mysql     = $mysql->pubsub(Mojo::mysql::PubSub->new);

L<Mojo::mysql::PubSub> should be considered an EXPERIMENT! See
L<Mojo::mysql::PubSub/DESCRIPTION> for more information.

=head2 username

  my $username = $mysql->username;
  $mysql       = $mysql->username('batman');

Database username, defaults to an empty string.

=head1 METHODS

L<Mojo::mysql> inherits all methods from L<Mojo::EventEmitter> and implements the
following new ones.

=head2 close_idle_connections

  $mysql = $mysql->close_idle_connections($keep);

Close all connections that are not currently active, or limit the
number of idle connections to C<$keep>.

=head2 db

  my $db = $mysql->db;

Get L<Mojo::mysql::Database> object for a cached or newly created database
handle. The database handle will be automatically cached again when that
object is destroyed, so you can handle connection timeouts gracefully by
holding on to it only for short amounts of time.

=head2 from_string

  $mysql = $mysql->from_string('mysql://user@/test');
  $mysql = $mysql->from_string(Mojo::URL->new);
  $mysql = $mysql->from_string(URI::db->new);

Parse configuration from connection string or a connection string object.

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
  my $mysql = Mojo::mysql->new(%attrs);
  my $mysql = Mojo::mysql->new(\%attrs);
  my $mysql = Mojo::mysql->new('mysql://user@/test');
  my $mysql = Mojo::mysql->new('mariadb://user@/test');

Construct a new L<Mojo::mysql> object either from L</ATTRIBUTES> and or parse
connection string with L</"from_string"> if necessary.

Using the "mariadb" scheme requires the optional module L<DBD::MariaDB> version
1.21 (or later) to be installed.

=head2 strict_mode

  my $mysql = Mojo::mysql->strict_mode('mysql://user@/test');
  my $mysql = $mysql->strict_mode($boolean);

This method can act as both a constructor and a method. When called as a
constructor, it will be the same as:

  my $mysql = Mojo::mysql->new('mysql://user@/test')->strict_mode(1);

Enabling strict mode will execute the following statement when a new connection
is created:

  SET SQL_MODE = CONCAT('ANSI,TRADITIONAL,ONLY_FULL_GROUP_BY,', @@sql_mode)
  SET SQL_AUTO_IS_NULL = 0

The idea is to set up a connection that makes it harder for MySQL to allow
"invalid" data to be inserted.

This method will not be removed, but the internal commands is subject to
change.

=head1 DEBUGGING

You can set the C<DBI_TRACE> environment variable to get some advanced
diagnostics information printed to C<STDERR> by L<DBI>.

  DBI_TRACE=1
  DBI_TRACE=15
  DBI_TRACE=15=dbitrace.log
  DBI_TRACE=SQL
  DBI_PROFILE=2

See also L<https://metacpan.org/pod/DBI#DBI_TRACE> and
L<https://metacpan.org/pod/DBI#DBI_PROFILE>.

=head1 REFERENCE

This is the class hierarchy of the L<Mojo::mysql> distribution.

=over 2

=item * L<Mojo::mysql>

=item * L<Mojo::mysql::Database>

=item * L<Mojo::mysql::Migrations>

=item * L<Mojo::mysql::PubSub>

=item * L<Mojo::mysql::Results>

=item * L<Mojo::mysql::Transaction>

=back

=head1 AUTHORS

This project is highly inspired by Sebastian Riedel's L<Mojo::Pg>.

=head2 Project Founder

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=head2 Contributors

=over 2


=item * Adam Hopkins <violapiratejunky@gmail.com>

=item * Alexander Karelas <alex.karelas@gmail.com>

=item * Curt Hochwender <hochwender@centurytel.net>

=item * Dan Book <grinnz@grinnz.com>

=item * Doug Bell <doug@preaction.me>

=item * Florian Heyer <info@heyer-it.de>

=item * Hernan Lopes <hernanlopes@gmail.com>

=item * Karl Rune Nilsen <krunen@gmail.com>

=item * Larry Leszczynski <larryl@emailplus.org>

=item * Lucas Tiago de Moraes <lucastiagodemoraes@gmail.com>

=item * Matt S Trout <mst@shadowcat.co.uk>

=item * Mike Magowan <mike@magowan.co.uk>

=item * Mohammad S Anwar <mohammad.anwar@yahoo.com>

=item * Rolf Stöckli <tekki@cpan.org>

=item * Sebastian Riedel <sri@cpan.org>

=item * Svetoslav Naydenov <harry@bix.bg>

=item * Svetoslav Naydenov <harryl@cpan.org>

=item * Tekki <tekki@tekki.ch>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014-2019, Jan Henning Thorsen.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 SEE ALSO

L<https://github.com/jhthorsen/mojo-mysql>,

L<Mojo::Pg> Async Connector for PostgreSQL using L<DBD::Pg>, L<https://github.com/kraih/mojo-pg>,

L<Mojo::MySQL5> Pure-Perl non-blocking I/O MySQL Connector, L<https://github.com/harry-bix/mojo-mysql5>,

L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
