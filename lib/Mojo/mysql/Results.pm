package Mojo::mysql::Results;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Util 'tablify';

sub array { croak 'Method "array" not implemented by subclass' }

sub arrays { croak 'Method "arrays" not implemented by subclass' }

sub columns { croak 'Method "columns" not implemented by subclass' }

sub hash { croak 'Method "hash" not implemented by subclass' }

sub hashes { croak 'Method "hashes" not implemented by subclass' }

sub rows { croak 'Method "rows" not implemented by subclass' }

sub text { tablify shift->arrays }

sub more_results { croak 'Method "more_results" not implemented by subclass' }

sub affected_rows { croak 'Method "affected_rows" not implemented by subclass' }

sub warnings_count { croak 'Method "warnings_count" not implemented by subclass' }

sub last_insert_id { croak 'Method "last_insert_id" not implemented by subclass' }

sub err { croak 'Method "err" not implemented by subclass' }

sub errstr { croak 'Method "errstr" not implemented by subclass' }

sub state { croak 'Method "state" not implemented by subclass' }

1;

=encoding utf8

=head1 NAME

Mojo::mysql::Results - abstract Results

=head1 SYNOPSIS

  package Mojo::mysql::Results::MyRes;
  use Mojo::Base 'Mojo::mysql::Results';

  sub array          {...}
  sub arrays         {...}
  sub columns        {...}
  sub hash           {...}
  sub hashes         {...}
  sub rows           {...}
  sub more_results   {...}
  sub affected_rows  {...}
  sub warnings_count {...}
  sub last_insert_id {...}
  sub err            {...}
  sub errstr         {...}
  sub state          {...}

=head1 DESCRIPTION

L<Mojo::mysql::Results> is abstract base class for Database results returned
by call to $db->L<query|Mojo::mysql::Database/"query">.

Implementations are L<Mojo::mysql::DBI::Results> and L<Mojo::mysql::Native::Results>.

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

=head2 err

  my $err = $results->err;

Error code receieved.

=head2 state

  my $state = $results->state;

Error state receieved.

=head2 errstr

  my $errstr = $results->errstr;

Error message receieved.

=head1 SEE ALSO

L<Mojo::mysql>.

=cut
