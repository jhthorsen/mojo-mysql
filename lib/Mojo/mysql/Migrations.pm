package Mojo::mysql::Migrations;
use Mojo::Base -base;
use Carp 'croak';
use Mojo::Loader;
use Mojo::Util 'slurp';
use constant DEBUG => $ENV{MOJO_MIGRATIONS_DEBUG} || 0;
has name => 'migrations';
has 'mysql';
sub active { $_[0]->_active($_[0]->mysql->db) }

sub from_data {
  my ($self, $class, $name) = @_;
  return $self->from_string(Mojo::Loader->new->data($class //= caller, $name // $self->name));
}
sub from_file { shift->from_string(slurp pop) }

sub from_string {
  my ($self, $sql) = @_;
  my ($version, $way);
  my $migrations = $self->{migrations} = {up => {}, down => {}};
  for my $line (split "\n", $sql // '') {
    ($version, $way) = ($1, lc $2) if $line =~ /^\s*--\s*(\d+)\s*(up|down)/i;
    $migrations->{$way}{$version} .= "$line\n" if $version;
  }
  return $self;
}
sub latest { (sort keys %{shift->{migrations}{up}})[-1] || 0 }


sub migrate {
  my ($self, $target) = @_;
  $target //= $self->latest;

# Unknown version
  my ($up, $down) = @{$self->{migrations}}{qw(up down)};
  croak "Version $target has no migration" if $target != 0 && !$up->{$target};

# Already the right version (make sure migrations table exists)
  my $db = $self->mysql->db;
  return $self if $self->_active($db) == $target;

# Lock migrations table and check version again
  local @{$db->dbh}{qw(AutoCommit RaiseError)} = (1, 1);
  my $tx = $db->begin;

  return $self if (my $active = $self->_active($db)) == $target;

# Up
  my $sql;
  if ($active < $target) {
    my @up = grep { $_ <= $target && $_ > $active } sort keys %$up;
    $sql = join '', map { $up->{$_} } @up;
  }

# Down
  else {
    my @down = grep { $_ > $target && $_ <= $active } reverse sort keys %$down;
    $sql = join '', map { $down->{$_} } @down;
  }
  warn "-- Migrate ($active -> $target)\n$sql\n" if DEBUG;
  chop($sql);
  $db->query($_) for split(';', $sql);
  $sql = 'update mojo_migrations set version = ? where name = ?;';
  $db->query($sql, $target, $self->name) and $tx->commit;
  return $self;
}

sub _active {
  my ($self, $db) = @_;
  my $dbh  = $db->dbh;
  my $name = $self->name;
  local @$dbh{qw(AutoCommit RaiseError)} = (1, 0);
  my $results = $db->query('select version from mojo_migrations where name = ?', $name);
  if (my $next = $results->array) { return $next->[0] }
  local @$dbh{qw(AutoCommit RaiseError)} = (1, 1);
  $db->query(
    'create table if not exists mojo_migrations (
       name    varchar(255) unique,
       version varchar(255) not null check (version >= 0)
     ) ENGINE=InnoDB'
  ) if $results->sth->err;
  $db->query('insert into mojo_migrations values (?, ?)', $name, 0);
  return 0;
}
1;

=encoding utf8
=head1 NAME
Mojo::mysql::Migrations - Migrations
=head1 SYNOPSIS
use Mojo::mysql::Migrations;
my $migrations = Mojo::mysql::Migrations->new(mysql => $mysql);
$migrations->from_file('/Users/sri/migrations.sql')->migrate;
=head1 DESCRIPTION
L<Mojo::mysql::Migrations> is used by L<Mojo::mysql> to allow database schemas to
evolve easily over time. A migration file is just a collection of sql blocks,
with one or more statements, separated by comments of the form
C<-- VERSION UP/DOWN>.
-- 1 up
create table messages (message text);
insert into messages values ('I ♥ Mojolicious!');
-- 1 down
drop table messages;
-- 2 up (...you can comment freely here...)
create table stuff (whatever int);
-- 2 down
drop table stuff;
The idea is to let you migrate from any version, to any version, up and down.
Postgres migrations are very safe because migrations are performed in transactions. 
MySQL, however, does not support DDL transactions. B<Therefore, migrations should 
be used with extreme caution. Backup your database. You've been warned.> 
Every set of migrations has a L</"name">, which is stored together with the 
currently active version in an automatically created table named C<mojo_migrations>.
=head1 ATTRIBUTES
L<Mojo::mysql::Migrations> implements the following attributes.
=head2 name
my $name = $migrations->name;
$migrations = $migrations->name('foo');
Name for this set of migrations, defaults to C<migrations>.
=head2 mysql
my $mysql = $migrations->mysql;
$migrations = $migrations->mysql(Mojo::mysql->new);
L<Mojo::mysql> object these migrations belong to.
=head1 METHODS
L<Mojo::mysql::Migrations> inherits all methods from L<Mojo::Base> and implements
the following new ones.
=head2 active
my $version = $migrations->active;
Currently active version.
=head2 from_data
$migrations = $migrations->from_data;
$migrations = $migrations->from_data('main');
$migrations = $migrations->from_data('main', 'file_name');
Extract migrations from a file in the DATA section of a class with
L<Mojo::Loader>, defaults to using the caller class and L</"name">.
__DATA__
@@ migrations
-- 1 up
create table messages (message text);
insert into messages values ('I ♥ Mojolicious!');
-- 1 down
drop table messages;
=head2 from_file
$migrations = $migrations->from_file('/Users/sri/migrations.sql');
Extract migrations from a file.
=head2 from_string
$migrations = $migrations->from_string(
'-- 1 up
create table foo (bar int);
-- 1 down
drop table foo;'
);
Extract migrations from string.
=head2 latest
my $version = $migrations->latest;
Latest version available.
=head2 migrate
$migrations = $migrations->migrate;
$migrations = $migrations->migrate(3);
Migrate from L</"active"> to a different version, up or down, defaults to
using L</"latest">. All version numbers need to be positive, with version C<0>
representing an empty database.
# Reset database
$migrations->migrate(0)->migrate;
=head1 DEBUGGING
You can set the C<MOJO_MIGRATIONS_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.
MOJO_MIGRATIONS_DEBUG=1
=head1 SEE ALSO
L<Mojo::mysql>, L<Mojolicious::Guides>, L<http://mojolicio.us>.
=cut
