package Mojo::mysql::URL;
use Mojo::Base 'Mojo::URL';

sub new { @_ > 1 ? shift->SUPER::new->parse(@_) : shift->SUPER::new }
 
sub parse {
  my ($self, $url) = @_;
  $self->SUPER::parse($url);

  $self->database($self->path->parts->[0] // '');

  if (($self->userinfo // '') =~ /^([^:]+)(?::([^:]+))?$/) {
    $self->username($1);
    $self->password($2) if defined $2;
  }

  my $hash = $self->query->to_hash;
  $self->{options} = {
    utf8 => 1,
    found_rows => 1,
    PrintError => 0,
    use_dbi => 1
  } unless exists $self->{options};

  @{$self->options}{keys %$hash} = values %$hash;

  return $self;
}

sub database {
  my $self = shift;
  return $self->{database} // '' unless @_;
  my $database = shift // '';
  $self->{database} = $database;
  return $self->path($database);
}

sub options {
  my $self = shift;
  return $self->{options} unless @_;
  $self->{options} = @_;
  return $self->query(@_);
}

sub password {
  my $self = shift;
  return $self->{password} // '' unless @_;
  $self->{password} = shift // '';
  return $self->userinfo($self->username . $self->password ? ':' . $self->password : '');
}

sub username {
  my $self = shift;
  return $self->{username} // '' unless @_;
  $self->{username} = shift // '';
  return $self->userinfo($self->username . $self->password ? ':' . $self->password : '');
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

=head2 options

  my $options  = $url->options;
  $url         = $url->options->{PrintError} = 1;

Database options.

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

  my $url = Mojo::mysql::URL->new('mysql://server:3000/test');
  # dbi:mysql:dbname=test;host=server;port=3000
  say $url->dsn;

Convert URL to L<DBI> Data Source Name.

=head2 parse

  $url->parse('mysql://server:3000/test');

Parse URL string.

=head2 new

  my $url = Mojo::mysql::URL->new;
  $url->parse('mysql://server:3000/test');

  my $url = Mojo::mysql::URL->new('mysql://server:3000/test');

=head1 SEE ALSO

L<Mojo::mysql>, L<Mojo::URL>.

=cut
