package Mojo::mysql::DBI::Transaction;
use Mojo::Base 'Mojo::mysql::Transaction';

sub DESTROY {
  my $self = shift;
  if ($self->{rollback} && (my $dbh = $self->{dbh})) { $dbh->rollback }
}

sub commit {
  my $self = shift;
  $self->{dbh}->commit if delete $self->{rollback};
}

sub new {
  my $self = shift->SUPER::new(@_, rollback => 1);
  $self->{dbh} = $self->db->dbh;
  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::mysql::DBI::Transaction - DBI Transaction

=head1 SYNOPSIS

  use Mojo::mysql::DBI::Transaction;

  my $tx = Mojo::mysql::DBI::Transaction->new(db => $db);
  $tx->commit;

=head1 DESCRIPTION

L<Mojo::mysql::DBI::Transaction> is a cope guard for L<DBD::mysql> transactions used by
L<Mojo::mysql::DBI::Database>.

=head1 ATTRIBUTES

L<Mojo::mysql::Transaction> implements the following attributes.

=head2 db

  my $db = $tx->db;
  $tx    = $tx->db(Mojo::mysql::Database->new);

L<Mojo::mysql::Database> object this transaction belongs to.

=head1 METHODS

L<Mojo::mysql::DBI::Transaction> inherits all methods from L<Mojo::mysql::Transaction> and
implements the following ones.

=head2 commit

  $tx = $tx->commit;

Commit transaction.

=head2 new

  my $tx = Mojo::mysql::DBI::Transaction->new;

Construct a new L<Mojo::mysql::DBI::Transaction> object.

=head1 SEE ALSO

L<Mojo::mysql::Transaction>, L<Mojo::mysql>.

=cut
