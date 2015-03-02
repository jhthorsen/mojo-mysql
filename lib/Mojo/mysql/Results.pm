package Mojo::mysql::Results;
use Mojo::Base -base;

use Mojo::Collection;
use Mojo::Util 'tablify';

has _columns => sub { [] };
has _results => sub { [] };
has _result => 0;
has _pos => 0;

sub _current_columns { $_[0]->_columns->[$_[0]->_result] }

sub _current_results { $_[0]->_results->[$_[0]->_result] // [] }

sub _hash {
  my ($self, $pos) = @_;
  return {
    map { $self->_current_columns->[$_]->{name} => $self->_current_results->[$pos]->[$_] }
    (0 .. scalar @{ $self->_current_columns } - 1)
  };
}


sub more_results {
  my $self = shift;
  return undef unless $self->_pos >= $self->rows;
  $self->{_pos} = 0;
  $self->{_result} ++;
  return $self->_result < scalar @{ $self->_results };
}

sub array {
  my $self = shift;
  return undef if $self->_pos >= $self->rows;
  my $array = $self->_current_results->[$self->_pos];
  $self->{_pos}++;
  return $array;
}

sub arrays {
  my $self = shift;
  my $arrays = Mojo::Collection->new(
    map { $self->_current_results->[$_] } ($self->_pos .. $self->rows - 1) );
  $self->{_pos} = $self->rows;
  return $arrays;
}

sub columns { [ map { $_->{name} } @{ shift->_current_columns } ] }

sub hash {
  my $self = shift;
  return undef if $self->_pos >= $self->rows;
  my $hash = $self->_hash($self->_pos);
  $self->{_pos}++;
  return $hash;
}

sub hashes {
  my $self = shift;
  my $hashes = Mojo::Collection->new(
    map { $self->_hash($_) } ($self->_pos .. $self->rows - 1) );
  $self->{_pos} = $self->rows;
  return $hashes;
}

sub rows { scalar @{ shift->_current_results } }

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

=head2 more_results

  do {
    my $columns = $results->columns;
    my $arrays = $results->arrays;
  } while ($results->more_results);

Handle multiple results.

=head1 SEE ALSO

L<Mojo::mysql>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
