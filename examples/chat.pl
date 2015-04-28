use Mojolicious::Lite;
use Mojo::mysql;

helper mysql => sub { state $mysql = Mojo::mysql->new('mysql://oss:prasw0RD@192.168.2.14/oss') };

get '/' => 'chat';

websocket '/channel' => sub {
  my $c = shift;

  $c->inactivity_timeout(3600);

  # Forward messages from the browser to PostgreSQL
  $c->on(message => sub { shift->mysql->pubsub->notify(mojochat => shift) });

  # Forward messages from PostgreSQL to the browser
  my $cb = $c->mysql->pubsub->listen(mojochat => sub { $c->send(pop) });
  $c->on(finish => sub { shift->mysql->pubsub->unlisten(mojochat => $cb) });
};

app->start;
__DATA__

@@ chat.html.ep
<form onsubmit="sendChat(this.children[0]); return false"><input></form>
<div id="log"></div>
<script>
  var ws  = new WebSocket('<%= url_for('channel')->to_abs %>');
  ws.onmessage = function (e) {
    document.getElementById('log').innerHTML += '<p>' + e.data + '</p>';
  };
  function sendChat(input) { ws.send(input.value); input.value = '' }
</script>
