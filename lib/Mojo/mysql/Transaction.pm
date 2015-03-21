package Mojo::mysql::Transaction;
use Mojo::Base -base;

use Carp 'croak';

has 'db';

sub commit { croak 'Method "commit" not implemented by subclass' }

1;

=encoding utf8

=head1 NAME

Mojo::mysql::Transaction - abstract Transaction

=head1 SYNOPSIS

  package Mojo::mysql::Transaction::MyTrans;
  use Mojo::Base 'Mojo::mysql::Transaction';

  sub commit  {...}
  sub DESTROY {...}

=head1 DESCRIPTION

L<Mojo::mysql::Transaction> is abstract base class for transactions
started by call to $db->L<begin|Mojo::mysql::Database/"begin">.

Implementations are L<Mojo::mysql::DBI::Transaction> and L<Mojo::mysql::Native::Transaction>.

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
