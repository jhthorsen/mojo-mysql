package Mojo::mysql::Results;
use Mojo::Base -base;

use Mojo::Collection;
use Mojo::Util 'tablify';

has dbh => undef;
has 'sth';

sub DESTROY {
  my $self = shift;
  $self->dbh ? $self->dbh->_destroy($self->sth) : $self->sth->finish;
}

sub array { shift->sth->fetchrow_arrayref }

sub arrays { Mojo::Collection->new(@{shift->sth->fetchall_arrayref}) }

sub columns { shift->sth->{NAME} }

sub hash { shift->sth->fetchrow_hashref }

sub hashes { Mojo::Collection->new(@{shift->sth->fetchall_arrayref({})}) }

sub rows { shift->sth->rows }

sub text { tablify shift->arrays }

1;

=encoding utf8

=head1 NAME

Mojo::mysql::Results - Results

=head1 SYNOPSIS

  use Mojo::mysql::Results;

  my $results = Mojo::mysql::Results->new(db => $db, sth => $sth);

=head1 DESCRIPTION

L<Mojo::mysql::Results> is a container for statement handles used by
L<Mojo::mysql::Database>.

=head1 ATTRIBUTES

L<Mojo::mysql::Results> implements the following attributes.

=head2 sth

  my $sth  = $results->sth;
  $results = $results->sth($sth);

Statement handle results are fetched from.

=head1 METHODS

L<Mojo::mysql::Results> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 array

  my $array = $results->array;

Fetch one row and return it as an array reference.

=head2 arrays

  my $collection = $results->arrays;

Fetch all rows and return them as a L<Mojo::Collection> object containing
array references.

=head2 columns

  my $columns = $results->columns;

Return column names as an array reference.

=head2 hash

  my $hash = $results->hash;

Fetch one row and return it as a hash reference.

=head2 hashes

  my $collection = $results->hashes;

Fetch all rows and return them as a L<Mojo::Collection> object containing hash
references.

=head2 rows

  my $num = $results->rows;

Number of rows.

=head2 text

  my $text = $results->text;

Fetch all rows and turn them into a table with L<Mojo::Util/"tablify">.

=head1 SEE ALSO

L<Mojo::mysql>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
