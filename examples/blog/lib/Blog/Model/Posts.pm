package Blog::Model::Posts;
use Mojo::Base -base;

has 'mysql';

sub all { shift->mysql->db->query('select * from posts')->hashes->each }

sub find {
  my ($self, $id) = @_;
  return $self->mysql->db->query('select * from posts where id = ?', $id)->hash;
}

sub publish {
  my ($self, $title, $body) = @_;
  my $sql = 'insert into posts (title, body) values (?, ?)';
  return $self->mysql->db->query($sql, $title, $body)->last_insert_id;
}

sub withdraw { shift->mysql->db->query('delete from posts where id = ?', shift) }

1;
