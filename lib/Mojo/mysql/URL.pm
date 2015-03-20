package Mojo::mysql::URL;
use Mojo::Base 'Mojo::URL';

sub database {
  my $self = shift;
  if (@_) {
    return $self->path(shift // '');
  }
  return $self->path->parts->[0] // '';
}

sub password {
  my $self = shift;
  if (@_) {
    my $password = shift;
    return $self->userinfo($self->username . $password ? ':' . $password : '');
  }
  return '' unless ($self->userinfo // '') =~ /^([^:]+)(?::([^:]+))?$/;
  return $2 // '';
}

sub username {
  my $self = shift;
  if (@_) {
    my $username = shift // '';
    return $self->userinfo($username . $self->password ? ':' . $self->password : '');
  }
  return '' unless ($self->userinfo // '') =~ /^([^:]+)(?::([^:]+))?$/;
  return $1;
}

sub dsn {
  my $self = shift;
  my $dsn = 'dbi:mysql:dbname=' . $self->database;
  $dsn .= ';host=' . $self->host if $self->host;
  $dsn .= ';port=' . $self->port if $self->port;
  return $dsn;
}

1;

=encoding utf8
 
=head1 NAME
 
Mojo::mysql::URL - MySQL Connection URL
 
=head1 SYNOPSIS
 
  use Mojo::mysql::URL;
 
  # Parse
  my $url = Mojo::mysql::URL->new('mysql://sri:foo@server:3306/test?foo=bar');
  say $url->username;
  say $url->password;
  say $url->host;
  say $url->port;
  say $url->database;
  say $url->query;
 
  # Build
  my $url = Mojo::mysql::URL->new;
  $url->scheme('mysql');
  $url->userinfo('sri:foobar');
  $url->host('server');
  $url->port(3306);
  $url->database('test');
  $url->query(foo => 'bar');
  say "$url";
 
=head1 DESCRIPTION
 
L<Mojo::mysql::URL> implements MySQL Connection string URL for using in L<Mojo::mysql>.
 
=head1 ATTRIBUTES
 
L<Mojo::mysql::URL> inherits all attributes from L<Mojo::URL> and implements the following new ones.

=head2 database

  my $db       = $url->database;
  $url         = $url->database('test');

Database name.

=head2 password

  my $password = $url->password;
  $url         = $url->password('s3cret');

Password part of URL.

=head2 username

  my $username = $url->username;
  $url         = $url->username('batman');

Username part of URL.

=head1 METHODS

L<Mojo::mysql::URL> inherits all methods from L<Mojo::URL> and implements the
following new ones.

=head2 dsn

Convert URL to L<DBI> Data Source Name.

=head1 SEE ALSO

L<Mojo::mysql>, L<Mojo::URL>.

=cut
