package Mojo::mysql::Results;
use Mojo::Base -base;

use Mojo::Collection;
use Mojo::Util 'tablify';

has qw(error error_state error_str affected_rows last_insert_id warnings_count);

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

  my $results = Mojo::mysql::Results->new;

=head1 DESCRIPTION

L<Mojo::mysql::Results> is a container for query results used by
L<Mojo::mysql::Database>.

=head1 ATTRIBUTES

L<Mojo::mysql::Results> implements the following attributes.

=head2 error

  my $error = $results->error;

Error code receieved.

=head2 error_state

  my $error_state = $results->error_state;

Error state receieved.

=head2 error_str

  my $error_str = $results->error_str;

Error message receieved.

=head2 affected_rows

  my $affected = $results->affected_rows;

Number of affected rows by the query.
The number reported is dependant from C<found_rows> option in L<Mojo::mysql>.
For example

  UPDATE $table SET id = 1 WHERE id = 1

would return 1 if C<found_rows> is set, and 0 otherwise.

=head2 last_insert_id

  my $last_id = $results->last_insert_id;

That value of C<AUTO_INCREMENT> column if executed query was C<INSERT> in a table with
C<AUTO_INCREMENT> column.

=head2 warnings_count

  my $warnings = $results->warnings_count;

Number of warnings raised by the executed query.

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
