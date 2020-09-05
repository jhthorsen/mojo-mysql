package Mojo::mysql::PubSub;
use Mojo::Base 'Mojo::EventEmitter';

use Scalar::Util 'weaken';

use constant DEBUG   => $ENV{MOJO_PUBSUB_DEBUG} || 0;
use constant RETRIES => $ENV{MOJO_MYSQL_PUBSUB_RETRIES} // 1;

has 'mysql';

sub DESTROY {
  my $self = shift;
  return unless $self->{wait_db} and $self->mysql;
  _query_with_retry($self->mysql->db, 'delete from mojo_pubsub_subscribe where pid = ?', $self->{wait_db}->pid);
}

sub listen {
  my ($self, $channel, $cb) = @_;
  my $sync_db  = $self->mysql->db;
  my $wait_pid = $self->_wait_db($sync_db)->pid;
  warn qq|[PubSub] (@{[$wait_pid]}) listen "$channel"\n| if DEBUG;
  _query_with_retry($sync_db,
    'insert into mojo_pubsub_subscribe (pid, channel) values (?, ?) on duplicate key update ts=current_timestamp',
    $wait_pid, $channel);
  push @{$self->{chans}{$channel}}, $cb;
  return $cb;
}

sub notify {
  my ($self, $channel, $payload) = @_;
  my $sync_db = $self->mysql->db;
  warn qq|[PubSub] channel:$channel <<< "@{[$payload // '']}"\n| if DEBUG;
  $self->_init($sync_db) unless $self->{init};
  _query_with_retry($sync_db, 'insert into mojo_pubsub_notify (channel, payload) values (?, ?)',
    $channel, $payload // '');
  return $self;
}

sub unlisten {
  my ($self, $channel, $cb) = @_;

  my $chan = $self->{chans}{$channel};
  @$chan = grep { $cb ne $_ } @$chan;
  return $self if @$chan;

  my $sync_db  = $self->mysql->db;
  my $wait_pid = $self->_wait_db($sync_db)->pid;
  warn qq|[PubSub] ($wait_pid) unlisten "$channel"\n| if DEBUG;
  _query_with_retry($sync_db, 'delete from mojo_pubsub_subscribe where pid = ? and channel = ?', $wait_pid, $channel);
  delete $self->{chans}{$channel};
  return $self;
}

sub _init {
  my ($self, $sync_db) = @_;
  $self->mysql->migrations->name('pubsub')->from_data->migrate;
  _query_with_retry($sync_db,
    'delete from mojo_pubsub_notify where ts < date_add(current_timestamp, interval -10 minute)');
  _query_with_retry($sync_db,
    'delete from mojo_pubsub_subscribe where ts < date_add(current_timestamp, interval -1 hour)');
  $self->{init} = 1;
}

sub _notifications {
  my ($self, $sync_db) = @_;
  my $result
    = _query_with_retry($sync_db, 'select id, channel, payload from mojo_pubsub_notify where id > ? order by id',
    $self->{last_id});
  while (my $row = $result->array) {
    my ($id, $channel, $payload) = @$row;
    $self->{last_id} = $id;
    next unless exists $self->{chans}{$channel};
    warn qq/[PubSub] channel:$channel >>> "$payload"\n/ if DEBUG;
    for my $cb (@{$self->{chans}{$channel}}) { $self->$cb($payload) }
  }
}

sub _wait_db {
  my ($self, $sync_db) = @_;

  # Fork-safety
  delete @$self{qw(wait_db chans pid)} if ($self->{pid} //= $$) ne $$;

  return $self->{wait_db} if $self->{wait_db};

  $self->_init($sync_db) unless $self->{init};
  my $wait_db     = $self->{wait_db} = $self->mysql->db;
  my $wait_db_pid = $wait_db->pid;
  _query_with_retry($sync_db,
    'insert into mojo_pubsub_subscribe (pid, channel) values (?, ?) on duplicate key update ts=current_timestamp',
    $wait_db_pid, $_)
    for keys %{$self->{chans}};

  if ($self->{last_id}) {
    $self->_notifications($sync_db);
  }
  else {
    my $last = _query_with_retry($sync_db, 'select id from mojo_pubsub_notify order by id desc limit 1')->array;
    $self->{last_id} = defined $last ? $last->[0] : 0;
  }

  weaken $wait_db->{mysql};
  weaken $self;
  my $cb;
  $cb = sub {
    my ($db, $err, $res) = @_;
    return unless $self;
    warn qq|[PubSub] (@{[$db->pid]}) sleep(600) @{[$err ? "!!! $err" : $res->array->[0]]}\n| if DEBUG;
    my $sync_db = $self->mysql->db;
    return (delete $self->{wait_db}, $self->_wait_db($sync_db)) if $err;
    $res->finish;
    _query_with_retry($db,      'select sleep(600)',                                                     $cb);
    _query_with_retry($sync_db, 'update mojo_pubsub_subscribe set ts = current_timestamp where pid = ?', $db->pid);
    $self->_notifications($self->mysql->db);
  };

  warn qq|[PubSub] (@{[$wait_db->pid]}) reconnect\n| if DEBUG;
  $self->emit(reconnect => $wait_db);
  return _query_with_retry($wait_db, 'select sleep(600)', $cb);
}

sub _query_with_retry {
  my ($db, $sql, @bind) = @_;

  my $result;

  my $remaining_attempts = RETRIES + 1;    # including initial attempt
  while ($remaining_attempts--) {
    local $@;
    eval { $result = $db->query($sql, @bind) };
    last     unless $@;                     # success
    croak $@ unless $remaining_attempts;    # rethrow $@ if no remaining attempts

    # If we are allowed to retry, check if the error message looks
    # like it refers to something retryable.  Only look within the
    # first line to avoid potential spurious matches if the error
    # e.g. contains a stack trace.
    my $err = $@;                                        # avoid stringifying $@ ...
    croak $@ unless $err =~ /^\V*(?:retry|timeout)/i;    # ... and maybe rethrow it

    # If we got here, we are retrying the query:
    warn qq|[PubSub] (@{[$db->pid]}) retry ($sql) !!! $err\n| if DEBUG;
  }

  return $result;
}

1;

=encoding utf8

=head1 NAME

Mojo::mysql::PubSub - Publish/Subscribe

=head1 SYNOPSIS

  use Mojo::mysql::PubSub;

  my $pubsub = Mojo::mysql::PubSub->new(mysql => $mysql);
  my $cb = $pubsub->listen(foo => sub {
    my ($pubsub, $payload) = @_;
    say "Received: $payload";
  });
  $pubsub->notify(foo => 'bar');
  $pubsub->unlisten(foo => $cb);

=head1 DESCRIPTION

L<Mojo::mysql::PubSub> is implementation of the publish/subscribe pattern used
by L<Mojo::mysql>. The implementation should be considered an EXPERIMENT and
might be removed without warning!

Although MySQL does not have C<SUBSCRIBE/NOTIFY> like PostgreSQL and other RDBMs,
this module implements similar feature.

Single Database connection waits for notification by executing C<SLEEP> on server.
C<connection_id> and subscribed channels in stored in C<mojo_pubsub_subscribe> table.
Inserting new row in C<mojo_pubsub_notify> table triggers C<KILL QUERY> for
all connections waiting for notification.

C<PROCESS> privilege is needed for MySQL user to see other users processes.
C<SUPER> privilege is needed to be able to execute C<KILL QUERY> for statements
started by other users. 
C<SUPER> privilege may be needed to be able to define trigger.

If your applications use this module using different MySQL users it is important
the migration script to be executed by user having C<SUPER> privilege on the database.

=head1 EVENTS

L<Mojo::mysql::PubSub> inherits all events from L<Mojo::EventEmitter> and can
emit the following new ones.

=head2 reconnect

  $pubsub->on(reconnect => sub {
    my ($pubsub, $db) = @_;
    ...
  });

Emitted after switching to a new database connection for sending and receiving
notifications.

=head1 ATTRIBUTES

L<Mojo::mysql::PubSub> implements the following attributes.

=head2 mysql

  my $mysql = $pubsub->mysql;
  $pubsub   = $pubsub->mysql(Mojo::mysql->new);

L<Mojo::mysql> object this publish/subscribe container belongs to.

=head1 METHODS

L<Mojo::mysql::PubSub> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 listen

  my $cb = $pubsub->listen(foo => sub {...});

Subscribe to a channel, there is no limit on how many subscribers a channel can
have.

  # Subscribe to the same channel twice
  $pubsub->listen(foo => sub {
    my ($pubsub, $payload) = @_;
    say "One: $payload";
  });
  $pubsub->listen(foo => sub {
    my ($pubsub, $payload) = @_;
    say "Two: $payload";
  });

=head2 notify

  $pubsub = $pubsub->notify('foo');
  $pubsub = $pubsub->notify(foo => 'bar');

Notify a channel.

=head2 unlisten

  $pubsub = $pubsub->unlisten(foo => $cb);

Unsubscribe from a channel.

=head1 DEBUGGING

You can set the C<MOJO_PUBSUB_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_PUBSUB_DEBUG=1

=head1 SEE ALSO

L<Mojo::mysql>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut

__DATA__

@@ pubsub
-- 1 down
drop table mojo_pubsub_subscribe;
drop table mojo_pubsub_notify;

-- 1 up
drop table if exists mojo_pubsub_subscribe;
drop table if exists mojo_pubsub_notify;

create table mojo_pubsub_subscribe (
  id integer auto_increment primary key,
  pid integer not null,
  channel varchar(64) not null,
  ts timestamp not null default current_timestamp,
  unique key subs_idx(pid, channel),
  key ts_idx(ts)
);

create table mojo_pubsub_notify (
  id integer auto_increment primary key,
  channel varchar(64) not null,
  payload text,
  ts timestamp not null default current_timestamp,
  key channel_idx(channel),
  key ts_idx(ts)
);

delimiter //

create trigger mojo_pubsub_notify_kill after insert on mojo_pubsub_notify
for each row
begin
  declare done boolean default false;
  declare t_pid integer;

  declare subs_c cursor for
  select pid from mojo_pubsub_subscribe where channel = NEW.channel;

  declare continue handler for not found set done = true;

  open subs_c;

  repeat
    fetch subs_c into t_pid;

    if not done and exists (
      select 1
        from INFORMATION_SCHEMA.PROCESSLIST
        where ID = t_pid and STATE = 'User sleep')
    then
      kill query t_pid;
    end if;

  until done end repeat;

  close subs_c;
end
//

delimiter ;
