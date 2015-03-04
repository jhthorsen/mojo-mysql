use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test'
  unless $ENV{TEST_ONLINE};

use Mojo::mysql;
use Mojolicious::Lite;
use Test::Mojo;

helper mysql => sub { state $mysql = Mojo::mysql->new($ENV{TEST_ONLINE}) };

app->mysql->migrations->name('app_test')->from_data->migrate;

get '/blocking' => sub {
  my $c  = shift;
  my $db = $c->mysql->db;
  $c->res->headers->header('X-PID' => $db->pid);
  $c->render(text => $db->query('select * from app_test')->hash->{stuff});
};

get '/non-blocking' => sub {
  my $c = shift;
  $c->mysql->db->query(
    'select * from app_test' => sub {
      my ($db, $err, $results) = @_;
      $c->res->headers->header('X-PID' => $db->pid);
      $c->render(text => $results->hash->{stuff});
    }
  );
};

my $t = Test::Mojo->new;

# Make sure migrations are not served as static files
$t->get_ok('/app_test')->status_is(404);

# Blocking select (with connection reuse)
$t->get_ok('/blocking')->status_is(200)->content_is('I ♥ Mojolicious!');
my $pid = $t->tx->res->headers->header('X-PID');
$t->get_ok('/blocking')->status_is(200)->header_is('X-PID', $pid)
  ->content_is('I ♥ Mojolicious!');

# Non-blocking select (with connection reuse)
$t->get_ok('/non-blocking')->status_is(200)->header_is('X-PID', $pid)
  ->content_is('I ♥ Mojolicious!');
$t->get_ok('/non-blocking')->status_is(200)->header_is('X-PID', $pid)
  ->content_is('I ♥ Mojolicious!');
$t->app->mysql->migrations->migrate(0);

done_testing();

__DATA__
@@ app_test
-- 1 up
create table if not exists app_test (stuff text);

-- 2 up
insert into app_test values ('I ♥ Mojolicious!');

-- 1 down
drop table app_test;
