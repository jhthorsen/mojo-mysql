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

=encoding utf8

=head1 NAME

Mojo::mysql::Native::Transaction - Transaction

=head1 SYNOPSIS

  use Mojo::mysql::Native::Transaction;

  my $tx = Mojo::mysql::Native::Transaction->new(db => $db);
  $tx->commit;

=head1 DESCRIPTION

L<Mojo::mysql::Native::Transaction> is a cope guard for transactions started by
$db->L<begin|Mojo::mysql::Native::Database/"begin">.

=head1 ATTRIBUTES

L<Mojo::mysql::Transaction> implements the following attributes.

=head2 db

  my $db = $tx->db;
  $tx    = $tx->db(Mojo::mysql::Native::Database->new);

L<Mojo::mysql::Native::Database> object this transaction belongs to.

=head1 METHODS

L<Mojo::mysql::Native::Transaction> inherits all methods from L<Mojo::mysql::Transaction> and
implements the following ones.

=head2 commit

  $tx = $tx->commit;

Commit transaction.

=head2 new

  my $tx = Mojo::mysql::Native::Transaction->new;

Construct a new L<Mojo::mysql::Native::Transaction> object.

=head1 SEE ALSO

L<Mojo::mysql::Transaction>, L<Mojo::mysql>.

=cut
