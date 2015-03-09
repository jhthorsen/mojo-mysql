package Mojo::mysql::Native::Transaction;
use Mojo::Base 'Mojo::mysql::Transaction';

sub DESTROY {
  my $self = shift;
  return unless $self->{rollback} and $self->db;
  local($@);
  $self->db->query('ROLLBACK');
  $self->db->query('SET autocommit=1');
}

sub commit {
  my $self = shift;
  return unless delete $self->{rollback};
  $self->db->query('COMMIT');
  $self->db->query('SET autocommit=1');
}

sub new {
  shift->SUPER::new(@_, rollback => 1);
}

1;
