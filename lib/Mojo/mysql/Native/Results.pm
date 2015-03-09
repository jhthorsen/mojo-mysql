package Mojo::mysql::Native::Results;
use Mojo::Base 'Mojo::mysql::Results';

use Mojo::Collection;

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

sub affected_rows { shift->{affected_rows} }

sub warnings_count { shift->{warnings_count} }

sub last_insert_id { shift->{last_insert_id} }

sub err { shift->{error_code} }

sub errstr { shift->{error_message} }

sub state { shift->{sql_state} // '' }

1;
