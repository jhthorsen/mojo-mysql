package Mojo::mysql::DBI::Results;
use Mojo::Base 'Mojo::mysql::Results';

use Mojo::Collection;

has 'sth';

sub array { shift->sth->fetchrow_arrayref }

sub arrays { Mojo::Collection->new(@{shift->sth->fetchall_arrayref}) }

sub columns { shift->sth->{NAME} }

sub hash { shift->sth->fetchrow_hashref }

sub hashes { Mojo::Collection->new(@{shift->sth->fetchall_arrayref({})}) }

sub rows { shift->sth->rows }

sub more_results { shift->sth->more_results }

sub affected_rows { shift->{affected_rows} }

sub warnings_count { shift->sth->{mysql_warning_count} }

sub last_insert_id { shift->sth->{mysql_insertid} }

sub err { shift->sth->err }

sub errstr { shift->sth->errstr }

sub state { shift->sth->state }

1;

=encoding utf8

=head1 NAME

Mojo::mysql::DBI::Results - DBD::mysql Results

=head1 SYNOPSIS

  use Mojo::mysql::DBI::Results;

  my $results = Mojo::mysql::DBI::Results->new(db => $db, sth => $sth);

=head1 DESCRIPTION

L<Mojo::mysql::DBI::Results> is a container for L<DBI> statement handles used by
L<Mojo::mysql::DBI::Database>.

=head1 ATTRIBUTES

L<Mojo::mysql::DBI::Results> implements the following attributes.

=head2 sth

  my $sth  = $results->sth;
  $results = $results->sth($sth);

Statement handle results are fetched from.

=head1 METHODS

L<Mojo::mysql::DBI::Results> inherits all methods from L<Mojo::mysql::Results> and implements
the following ones.

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

L<Mojo::mysql::Results>, L<Mojo::mysql>.

=cut
