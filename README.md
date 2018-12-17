# NAME

Mojo::mysql - Mojolicious and Async MySQL

# SYNOPSIS

    use Mojo::mysql;

    # Connect to a local database
    my $mysql = Mojo::mysql->strict_mode('mysql://username@/test');

    # Connect to a remote database
    my $mysql = Mojo::mysql->strict_mode('mysql://username:password@hostname/test');
    # MySQL >= 8.0:
    my $mysql = Mojo::mysql->strict_mode('mysql://username:password@hostname/test;mysql_ssl=1');

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

    # Send and receive notifications non-blocking
    $mysql->pubsub->listen(foo => sub {
      my ($pubsub, $payload) = @_;
      say "foo: $payload";
      $pubsub->notify(bar => $payload);
    });
    $mysql->pubsub->listen(bar => sub {
      my ($pubsub, $payload) = @_;
      say "bar: $payload";
    });
    $mysql->pubsub->notify(foo => 'MySQL rocks!');

    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

# DESCRIPTION

[Mojo::mysql](https://metacpan.org/pod/Mojo::mysql) is a tiny wrapper around [DBD::mysql](https://metacpan.org/pod/DBD::mysql) that makes
[MySQL](http://www.mysql.org) a lot of fun to use with the
[Mojolicious](http://mojolicio.us) real-time web framework.

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
queries asynchronously, allowing the [Mojo::IOLoop](https://metacpan.org/pod/Mojo::IOLoop) event loop to perform
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
been forked, this allows multiple processes to share the same [Mojo::mysql](https://metacpan.org/pod/Mojo::mysql)
object safely.

# EVENTS

[Mojo::mysql](https://metacpan.org/pod/Mojo::mysql) inherits all events from [Mojo::EventEmitter](https://metacpan.org/pod/Mojo::EventEmitter) and can emit the
following new ones.

## connection

    $mysql->on(connection => sub {
      my ($mysql, $dbh) = @_;
      ...
    });

Emitted when a new database connection has been established.

# ATTRIBUTES

[Mojo::mysql](https://metacpan.org/pod/Mojo::mysql) implements the following attributes.

## abstract

    $abstract = $mysql->abstract;
    $mysql    = $mysql->abstract(SQL::Abstract::mysql->new);

[SQL::Abstract::mysql](https://metacpan.org/pod/SQL::Abstract::mysql) object used to generate CRUD queries for [Mojo::mysql::Database](https://metacpan.org/pod/Mojo::mysql::Database).

    # Generate statements and bind values
    my ($stmt, @bind) = $mysql->abstract->select('names');

## auto\_migrate

    my $bool = $mysql->auto_migrate;
    $mysql   = $mysql->auto_migrate($bool);

Automatically migrate to the latest database schema with ["migrations"](#migrations), as
soon as the first database connection has been established.

Defaults to false.

## close\_idle\_connections

    $mysql = $mysql->close_idle_connections;

Close all connections that are not currently active.

## database\_class

    $class = $mysql->database_class;
    $mysql = $mysql->database_class("MyApp::Database");

Class to be used by ["db"](#db), defaults to [Mojo::mysql::Database](https://metacpan.org/pod/Mojo::mysql::Database). Note that this
class needs to have already been loaded before ["db"](#db) is called.

## dsn

    my $dsn = $mysql->dsn;
    $mysql  = $mysql->dsn('dbi:mysql:dbname=foo');

Data Source Name, defaults to `dbi:mysql:dbname=test`.

## max\_connections

    my $max = $mysql->max_connections;
    $mysql  = $mysql->max_connections(3);

Maximum number of idle database handles to cache for future use, defaults to
`5`.

## migrations

    my $migrations = $mysql->migrations;
    $mysql         = $mysql->migrations(Mojo::mysql::Migrations->new);

[Mojo::mysql::Migrations](https://metacpan.org/pod/Mojo::mysql::Migrations) object you can use to change your database schema more
easily.

    # Load migrations from file and migrate to latest version
    $mysql->migrations->from_file('/Users/sri/migrations.sql')->migrate;

MySQL does not support nested transactions and DDL transactions.
DDL statements cause implicit `COMMIT`. `ROLLBACK` will be called if
any step of migration script fails, but only DML statements after the
last implicit or explicit `COMMIT` can be reverted.
Not all MySQL storage engines (like `MYISAM`) support transactions.

This means database will most likely be left in unknown state if migration script fails.
Use this feature with caution and remember to always backup your database.

## options

    my $options = $mysql->options;
    $mysql      = $mysql->options({mysql_use_result => 1});

Options for database handles, defaults to activating `mysql_enable_utf8`, `AutoCommit`,
`AutoInactiveDestroy` as well as `RaiseError` and deactivating `PrintError`.
Note that `AutoCommit` and `RaiseError` are considered mandatory, so
deactivating them would be very dangerous.

`mysql_auto_reconnect` is never enabled, [Mojo::mysql](https://metacpan.org/pod/Mojo::mysql) takes care of dead connections.

`AutoCommit` cannot not be disabled, use $db->[begin](https://metacpan.org/pod/Mojo::mysql::Database#begin) to manage transactions.

`RaiseError` is enabled for blocking and disabled in event loop for non-blocking queries.

Note about `mysql_enable_utf8`:

    The mysql_enable_utf8 sets the utf8 charset which only supports up to 3-byte
    UTF-8 encodings. mysql_enable_utf8mb4 (as of DBD::mysql 4.032) properly
    supports encoding unicode characters to up to 4 bytes, such as 𠜎. It means the
    connection charset will be utf8mb4 (supported back to at least mysql 5.5) and
    these unicode characters will be supported, but no other changes.

See also [https://github.com/jhthorsen/mojo-mysql/pull/32](https://github.com/jhthorsen/mojo-mysql/pull/32)

## password

    my $password = $mysql->password;
    $mysql       = $mysql->password('s3cret');

Database password, defaults to an empty string.

## pubsub

    my $pubsub = $mysql->pubsub;
    $mysql     = $mysql->pubsub(Mojo::mysql::PubSub->new);

[Mojo::mysql::PubSub](https://metacpan.org/pod/Mojo::mysql::PubSub) object you can use to send and receive notifications very
efficiently, by sharing a single database connection with many consumers.

    # Subscribe to a channel
    $mysql->pubsub->listen(news => sub {
      my ($pubsub, $payload) = @_;
      say "Received: $payload";
    });

    # Notify a channel
    $mysql->pubsub->notify(news => 'MySQL rocks!');

Note that [Mojo::mysql::PubSub](https://metacpan.org/pod/Mojo::mysql::PubSub) should be considered an experiment!

## username

    my $username = $mysql->username;
    $mysql       = $mysql->username('batman');

Database username, defaults to an empty string.

# METHODS

[Mojo::mysql](https://metacpan.org/pod/Mojo::mysql) inherits all methods from [Mojo::EventEmitter](https://metacpan.org/pod/Mojo::EventEmitter) and implements the
following new ones.

## db

    my $db = $mysql->db;

Get [Mojo::mysql::Database](https://metacpan.org/pod/Mojo::mysql::Database) object for a cached or newly created database
handle. The database handle will be automatically cached again when that
object is destroyed, so you can handle connection timeouts gracefully by
holding on to it only for short amounts of time.

## from\_string

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

## new

    my $mysql = Mojo::mysql->new;
    my $mysql = Mojo::mysql->new(%attrs);
    my $mysql = Mojo::mysql->new(\%attrs);
    my $mysql = Mojo::mysql->new('mysql://user@/test');

Construct a new [Mojo::mysql](https://metacpan.org/pod/Mojo::mysql) object either from ["ATTRIBUTES"](#attributes) and or parse
connection string with ["from\_string"](#from_string) if necessary.

## strict\_mode

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

# DEBUGGING

You can set the `DBI_TRACE` environment variable to get some advanced
diagnostics information printed to `STDERR` by [DBI](https://metacpan.org/pod/DBI).

    DBI_TRACE=1
    DBI_TRACE=15
    DBI_TRACE=15=dbitrace.log
    DBI_TRACE=SQL
    DBI_PROFILE=2

See also [https://metacpan.org/pod/DBI#DBI\_TRACE](https://metacpan.org/pod/DBI#DBI_TRACE) and
[https://metacpan.org/pod/DBI#DBI\_PROFILE](https://metacpan.org/pod/DBI#DBI_PROFILE).

# REFERENCE

This is the class hierarchy of the [Mojo::mysql](https://metacpan.org/pod/Mojo::mysql) distribution.

- [Mojo::mysql](https://metacpan.org/pod/Mojo::mysql)
- [Mojo::mysql::Database](https://metacpan.org/pod/Mojo::mysql::Database)
- [Mojo::mysql::Migrations](https://metacpan.org/pod/Mojo::mysql::Migrations)
- [Mojo::mysql::PubSub](https://metacpan.org/pod/Mojo::mysql::PubSub)
- [Mojo::mysql::Results](https://metacpan.org/pod/Mojo::mysql::Results)
- [Mojo::mysql::Transaction](https://metacpan.org/pod/Mojo::mysql::Transaction)

# AUTHOR

Curt Hochwender - `hochwender@centurytel.net`.

Dan Book - `dbook@cpan.org`

Jan Henning Thorsen - `jhthorsen@cpan.org`.

Mike Magowan

This code is mostly a rip-off from Sebastian Riedel's [Mojo::Pg](https://metacpan.org/pod/Mojo::Pg).

# COPYRIGHT AND LICENSE

Copyright (C) 2014-2015, Jan Henning Thorsen.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

# SEE ALSO

[https://github.com/jhthorsen/mojo-mysql](https://github.com/jhthorsen/mojo-mysql),

[Mojo::Pg](https://metacpan.org/pod/Mojo::Pg) Async Connector for PostgreSQL using [DBD::Pg](https://metacpan.org/pod/DBD::Pg), [https://github.com/kraih/mojo-pg](https://github.com/kraih/mojo-pg),

[Mojo::MySQL5](https://metacpan.org/pod/Mojo::MySQL5) Pure-Perl non-blocking I/O MySQL Connector, [https://github.com/harry-bix/mojo-mysql5](https://github.com/harry-bix/mojo-mysql5),

[Mojolicious::Guides](https://metacpan.org/pod/Mojolicious::Guides), [http://mojolicio.us](http://mojolicio.us).
