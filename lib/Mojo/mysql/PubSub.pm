package Mojo::mysql::PubSub;
use Mojo::Base 'Mojo::EventEmitter';

use Scalar::Util 'weaken';

has 'mysql';

sub listen {
  my ($self, $name, $cb) = @_;
  my $sleeping = $self->_db;
  my $sql = @{$self->{chans}{$name} ||= []} ?
    'update mojo_pubsub_subscribe set ts = current_timestamp where pid = ? and channel = ?' :
    'insert into mojo_pubsub_subscribe(pid, channel) values (?, ?)';
  $self->mysql->db->query($sql, $sleeping->pid, $name);
  push @{$self->{chans}{$name}}, $cb;
  return $cb;
}

sub notify {
  my ($self, $name, $payload) = @_;
  $self->_db;
  $self->mysql->db->query(
    'insert into mojo_pubsub_notify(channel, message) values (?, ?)', $name, $payload);
  return $self;
}

sub unlisten {
  my ($self, $name, $cb) = @_;
  my $chan = $self->{chans}{$name};
  @$chan = grep { $cb ne $_ } @$chan;
  return $self if @$chan;
  my $sleeping = $self->_db;
  $self->mysql->db->query(
    'delete from mojo_pubsub_subscribe where pid = ? and channel = ?',
    $sleeping->pid, $name);
  delete $self->{chans}{$name};
  return $self;
}

sub _db {
  my $self = shift;

  # Fork-safety
  delete @$self{qw(chans pid)} and $self->{db} and $self->{db}->disconnect
    unless ($self->{pid} //= $$) eq $$;

  return $self->{db} if $self->{db};

  $self->mysql->migrations->from_data(__PACKAGE__, 'pubsub')->migrate;

  my $db = $self->{db} = $self->mysql->db;

  # id of the last message in table
  if (!defined $self->{last_id}) {
    my $array = $db->query(
      'select id from mojo_pubsub_notify order by id desc limit 1')->array;
    $self->{last_id} = defined $array ? $array->[0] : 0;
  }

  # cleanup old subscriptions and notifications
  $db->query(
    'delete from mojo_pubsub_notify where ts < date_add(current_timestamp, interval -10 minute)');
  $db->query(
    'delete from mojo_pubsub_subscribe where ts < date_add(current_timestamp, interval -1 hour)');

  # re-subscribe
  $db->query(
    'delete from mojo_pubsub_subscribe where pid = ?', $db->pid);
  $db->query(
    'insert into mojo_pubsub_subscribe(pid, channel) values (?, ?)', $db->pid, $_)
    for keys %{$self->{chans}};

  weaken $db->{mysql};
  weaken $self;

  my $cb;
  $cb = sub {
    $db->query(
      'select id, channel, message from mojo_pubsub_notify where id > ?',
      $self->{last_id})->hashes->each(
      sub {
        my ($id, $channel, $payload) = ($_->{id}, $_->{channel}, $_->{message});
        $self->{last_id} = $id;
        return unless exists $self->{chans}{$channel};
        for my $cb (@{$self->{chans}{$channel}}) { $self->$cb($payload) }
      }
    );
    $db->query('update mojo_pubsub_subscribe set ts = current_timestamp where pid = ?', $db->pid);
    $db->query('select sleep(600)', $cb);
  };
  $db->query('select sleep(600)', $cb);

  $self->emit(reconnect => $db);

  return $db;
}

1;

__DATA__

@@ pubsub
-- 1 up
drop table if exists mojo_pubsub_subscribe;
drop table if exists mojo_pubsub_notify;
drop trigger if exists mojo_pubsub_notify_kill;

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
  message varchar(256),
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

    if not done
    then
      if exists (select 1
        from INFORMATION_SCHEMA.PROCESSLIST
        where ID = t_pid and STATE = 'User sleep')
      then 
        kill query t_pid;
      end if;
    end if;

  until done end repeat;

  close subs_c;
end
//

delimiter ;
