package Mojo::mysql::Results;
use Mojo::Base -base;

use Mojo::Collection;
use Mojo::Util 'tablify';

has 'sth';

sub array { shift->sth->fetchrow_arrayref }

sub arrays { Mojo::Collection->new(@{shift->sth->fetchall_arrayref}) }

sub columns { shift->sth->{NAME} }

sub finish { shift->sth->finish }

sub hash { shift->sth->fetchrow_hashref }

sub hashes { Mojo::Collection->new(@{shift->sth->fetchall_arrayref({})}) }

sub rows { shift->sth->rows }

sub text { tablify shift->arrays }

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

Fetch next row from L</"sth"> and return it as an array reference. Note that
L</"finish"> needs to be called if you are not fetching all the possible rows.

  # Process one row at a time
  while (my $next = $results->array) {
    say $next->[3];
  }

=head2 arrays

  my $collection = $results->arrays;

Fetch all rows and return them as a L<Mojo::Collection> object containing
array references.

  # Process all rows at once
  say $results->arrays->reduce(sub { $a->[3] + $b->[3] });

=head2 columns

  my $columns = $results->columns;

Return column names as an array reference.

=head2 finish

  $results->finish;

Indicate that you are finished with L</"sth"> and will not be fetching all the
remaining rows.

=head2 hash

  my $hash = $results->hash;

Fetch next row from L</"sth"> and return it as a hash reference. Note that
L</"finish"> needs to be called if you are not fetching all the possible rows.

  # Process one row at a time
  while (my $next = $results->hash) {
    say $next->{money};
  }

=head2 hashes

  my $collection = $results->hashes;

Fetch all rows and return them as a L<Mojo::Collection> object containing hash
references.

  # Process all rows at once
  say $results->hashes->reduce(sub { $a->{money} + $b->{money} });

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
