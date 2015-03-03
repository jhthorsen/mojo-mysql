package Mojo::mysql::Util;
use Mojo::Base -strict;
use Exporter 'import';

our @EXPORT_OK = qw(quote quote_identifier expand_sql);

sub quote {
	my $string = shift;
	return 'NULL' unless defined $string;

	for ($string) {
		s/\\/\\\\/g;
		s/\0/\\0/g;
		s/\n/\\n/g;
		s/\r/\\r/g;
		s/'/\\'/g;
		# s/"/\\"/g;
		s/\x1a/\\Z/g;
	}

	return "'$string'";
}

sub quote_identifier {
	my $id = shift;
	return 'NULL' unless defined $id;
	$id =~ s/`/``/g;
	return "`$id`";
}

# from Net::Wire10
my $split_sql = qr/
  # capture each part, which is either:
  (
    # small comment in double-dash or
    --[[:cntrl:]\ ].*(?:\n|\z) |
    # small comment in hash or
    \#.*(?:\n|\z) |
    # big comment in C-style or version-conditional code or
    \/\*(?:[^\*]|\*[^\/])*(?:\*\/|\*\z|\z) |
    # whitespace
    [\ \r\n\013\t\f]+ |
    # single-quoted literal text or
    '(?:[^'\\]*|\\(?:.|\n)|'')*(?:'|\z) |
    # double-quoted literal text or
    "(?:[^"\\]*|\\(?:.|\n)|"")*(?:"|\z) |
    # schema-quoted literal text or
    `(?:[^`]*|``)*(?:`|\z) |
    # else it is either sql speak or
    (?:[^'"`\?\ \r\n\013\t\f\#\-\/]|\/[^\*]|-[^-]|--(?=[^[:cntrl:]\ ]))+ |
    # bingo: a ? placeholder
    \?
  )
/x;

sub expand_sql {
  my ($sql, @args) = @_;
  my @sql = $sql =~ m/$split_sql/g;
  return join('', map { $_ eq '?' ? quote(shift @args) : $_ } @sql);
}

1;

=encoding utf8
 
=head1 NAME
 
Mojo::mysql::Util - Utility functions
 
=head1 SYNOPSIS
 
  use Mojo::mysql::Util qw(quote quote_identifier);
 
  my $str = "I'm happy\n";
  my $escaped = quote $str;
 
=head1 DESCRIPTION
 
L<Mojo::mysql::Util> provides utility functions for L<Mojo::mysql>.
 
=head1 FUNCTIONS
 
L<Mojo::mysql::Util> implements the following functions, which can be imported
individually.
 
=head2 quote
 
  my $escaped = quote $str;
 
Quote string value for passing to SQL query.
 
=head2 quote_identifier
 
  my $escaped = quote_identifier $id;
 
Quote identifier for passing to SQL query.

=head2 expand_sql
 
  my $sql = expand_sql("select name from table where id=?", $id);
 
Replace ? in SQL query with quoted arguments.
 
=cut


