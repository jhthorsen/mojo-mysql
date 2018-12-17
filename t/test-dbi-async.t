#!/usr/bin/env perl
use Mojo::Base -strict;

use DBI;
use Mojo::IOLoop;
use Test::More;

# This is not a real test for Mojo::mysql, but it's a test to see if I have
# understood how async works.
# - jhthorsen

plan skip_all => 'TEST_DBI_ASYNC=1' unless $ENV{TEST_DBI_ASYNC};

my ($dbh, $dsn, $rv);

# Check if there's a difference between the MySQL and MariaDB driver
for (qw(dbi:mysql: dbi:MariaDB:)) {
  $dsn = $_;

  note "$dsn connect";
  $dbh = DBI->connect($dsn, 'root', undef, {PrintError => 0, PrintWarn => 1, RaiseError => 1});

  note "$dsn should not fail, since the driver is not yet in async mode";
  test_sync_select(40);

  note "$dsn should not fail, since the sync request is done";
  my @sth = ($dbh->prepare('SELECT SLEEP(1), 11', $dsn =~ /MariaDB/ ? {mariadb_async => 1} : {async => 1}));
  $sth[0]->execute;

  note "$dsn fails with: We cannot switch to blocking, when async is in process";
  test_sync_select(41);

  my $fd_method     = $dsn =~ /MariaDB/ ? 'mariadb_sockfd'       : 'mysql_fd';
  my $ready_method  = $dsn =~ /MariaDB/ ? 'mariadb_async_ready'  : 'mysql_async_ready';
  my $result_method = $dsn =~ /MariaDB/ ? 'mariadb_async_result' : 'mysql_async_result';

  open my $fd, '<&', $dbh->$fd_method or die "Dup mariadb_sockfd: $!";
  Mojo::IOLoop->singleton->reactor->io(
    $fd => sub {
      return unless $sth[-1]->$ready_method;

      # DBD::mysql::st mysql_async_result failed: Gathering async_query_in_flight results for the wrong handle
      # $sth[0]->$result_method;

      $rv = do { local $sth[-1]->{RaiseError} = 0; $sth[-1]->$result_method; };
      return Mojo::IOLoop->stop if @sth == 2;

      note "$dsn need to prepare/execute after the first is ready";
      push @sth, $dbh->prepare('SELECT SLEEP(1), 22', $dsn =~ /MariaDB/ ? {mariadb_async => 1} : {async => 1});
      $sth[1]->execute;
    }
  )->watch($fd, 1, 0);

  Mojo::IOLoop->start;

  note "$dsn sync works as long as the async is done";
  test_sync_select(42);

  note "$dsn async fetchrow_arrayref+finish order does not matter";
  is_deeply $sth[1]->fetchrow_arrayref, [0, 22], "$dsn SELECT SLEEP(1), 22";
  ok eval { $sth[1]->finish; 1 }, 'finish is also successful' or diag "$dsn: $@";

  note "$dsn async fetchrow_arrayref works afterwards";
  is_deeply $sth[0]->fetchrow_arrayref, [0, 11], "$dsn SELECT SLEEP(1), 11";
  ok eval { $sth[0]->finish; 1 }, 'finish is also successful' or diag "$dsn: $@";

  test_sync_select(42);

  note "$dsn need to clean up the sth before dbh";
  @sth = ();
  undef $dbh;
}

done_testing;

sub test_sync_select {
  my $num = shift;
  eval {
    my $sth_sync = $dbh->prepare("SELECT $num as num");
    $sth_sync->execute;
    is $sth_sync->fetchrow_arrayref->[0], $num, "$dsn SELECT $num as num";
    1;
  } or do {
    if ($num eq '41') {
      like $@, qr{Calling a synchronous function on an asynchronous handle}, "$dsn cannot switch from async to sync";
    }
    else {
      is $@, $num, "$dsn SELECT $num as num";
    }
  };
}
