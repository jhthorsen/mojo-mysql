package Mojo::mysql::PubSub;
use Mojo::Base 'Mojo::EventEmitter';

use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_PUBSUB_DEBUG} || 0;

has 'mysql';

sub DESTROY {
  my $self = shift;
  return unless $self->{db} and $self->mysql;
  $self->mysql->db->query('delete from mojo_pubsub_subscribe where pid = ?', $self->_subscriber_pid);
}

sub listen {
  my ($self, $channel, $cb) = @_;
  my $pid = $self->_subscriber_pid;
  warn "listen channel:$channel subscriber:$pid\n" if DEBUG;
  $self->mysql->db->query('replace mojo_pubsub_subscribe(pid, channel, ts) values (?, ?, current_timestamp)',
    $pid, $channel);
  push @{$self->{chans}{$channel}}, $cb;
  return $cb;
}

sub notify {
  my ($self, $channel, $payload) = @_;
  my $db = $self->mysql->db;
  $payload //= '';
  warn "notify channel:$channel $payload\n" if DEBUG;
  $self->_init($db) unless $self->{init}++;
  $db->query('insert into mojo_pubsub_notify(channel, payload) values (?, ?)', $channel, $payload);
  return $self;
}

sub unlisten {
  my ($self, $channel, $cb) = @_;
  my $pid = $self->_subscriber_pid;
  warn "unlisten channel:$channel subscriber:$pid\n" if DEBUG;
  my $chan = $self->{chans}{$channel};
  @$chan = grep { $cb ne $_ } @$chan;
  return $self if @$chan;
  $self->mysql->db->query('delete from mojo_pubsub_subscribe where pid = ? and channel = ?', $pid, $channel);
  delete $self->{chans}{$channel};
  return $self;
}

sub _notifications {
  my $self = shift;
  my $result = $self->{db}->query('select id, channel, payload from mojo_pubsub_notify where id > ?', $self->{last_id});

  while (my $row = $result->array) {
    my ($id, $channel, $payload) = @$row;
    $self->{last_id} = $id;
    next unless exists $self->{chans}{$channel};
    warn "received $id on $channel: $payload\n" if DEBUG;
    for my $cb (@{$self->{chans}{$channel}}) { $self->$cb($payload) }
  }
}

sub _init {
  my ($self, $db) = @_;

  $self->mysql->migrations->name('pubsub')->from_data->migrate;

  # cleanup old subscriptions and notifications
  $db->query('delete from mojo_pubsub_notify where ts < date_add(current_timestamp, interval -10 minute)');
  $db->query('delete from mojo_pubsub_subscribe where ts < date_add(current_timestamp, interval -1 hour)');
}

sub _subscriber_pid {
  my $self = shift;

  # Fork-safety
  if (($self->{pid} //= $$) ne $$) {
    my $pid = $self->{db}->pid if $self->{db};
    warn 'forked subscriber pid:' . ($pid || 'N/A') . "\n" if DEBUG;
    $self->{db}->disconnect if $pid;
    delete @$self{qw(chans init pid db)};
  }

  return $self->{db}->pid if $self->{db};

  $self->{db} = $self->mysql->db;
  my $pid = $self->{db}->pid;

  $self->_init($self->{db}) unless $self->{init}++;

  if (defined $self->{last_id}) {

    # read unread notifications
    $self->_notifications;
  }
  else {
    # get id of the last message
    my $array = $self->{db}->query('select id from mojo_pubsub_notify order by id desc limit 1')->array;
    $self->{last_id} = defined $array ? $array->[0] : 0;
  }

  # re-subscribe
  $self->{db}->query('replace mojo_pubsub_subscribe(pid, channel) values (?, ?)', $pid, $_) for keys %{$self->{chans}};

  weaken $self->{db}->{mysql};
  weaken $self;

  my $cb;
  $cb = sub {
    my ($db, $err, $result) = @_;
    if ($err) {
      warn "wake up error: $err" if DEBUG;
      eval { $db->disconnect };
      delete $self->{db};
      eval { $self->_subscriber_pid };
    }
    elsif ($self and $self->{db}) {
      $self->_notifications;
      $db->query('update mojo_pubsub_subscribe set ts = current_timestamp where pid = ?', $pid);
      $db->query('select sleep(600)',                                                     $cb);
    }
  };
  $self->{db}->query('select sleep(600)', $cb);

  warn "reconnect subscriber pid: $pid\n" if DEBUG;
  $self->emit(reconnect => $self->{db});

  return $pid;
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
by L<Mojo::mysql>. The implementation should be considered an experiment and
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

create table mojo_pubsub_subscribe(
  id integer auto_increment primary key,
  pid integer not null,
  channel varchar(64) not null,
  ts timestamp not null default current_timestamp,
  unique key subs_idx(pid, channel),
  key ts_idx(ts)
);

create table mojo_pubsub_notify(
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
