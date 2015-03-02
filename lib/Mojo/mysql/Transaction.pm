package Mojo::mysql::Transaction;
use Mojo::Base -base;

has 'db';

sub DESTROY {
  my $self = shift;
  return unless $self->{rollback} and $self->db;
  $self->db->do('ROLLBACK');
}

sub commit {
  my $self = shift;
  $self->db->do('COMMIT') if delete $self->{rollback};
}

sub new {
  shift->SUPER::new(@_, rollback => 1);
}

1;

=encoding utf8

=head1 NAME

Mojo::mysql::Transaction - Transaction

=head1 SYNOPSIS

  use Mojo::mysql::Transaction;

  my $tx = Mojo::mysql::Transaction->new(db => $db);
  $tx->commit;

=head1 DESCRIPTION

L<Mojo::mysql::Transaction> is a cope guard for L<DBD::mysql> transactions used by
L<Mojo::mysql::Database>.

=head1 ATTRIBUTES

L<Mojo::mysql::Transaction> implements the following attributes.

=head2 db

  my $db = $tx->db;
  $tx    = $tx->db(Mojo::mysql::Database->new);

L<Mojo::mysql::Database> object this transaction belongs to.

=head1 METHODS

L<Mojo::mysql::Transaction> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 commit

  $tx = $tx->commit;

Commit transaction.

=head2 new

  my $tx = Mojo::mysql::Transaction->new;

Construct a new L<Mojo::mysql::Transaction> object.

=head1 SEE ALSO

L<Mojo::mysql>.

=cut
