use Mojo::Base -strict;

use Test::More;

use Mojo::mysql::Connection;

my $c = Mojo::mysql::Connection->new;

$c->{incoming} = Mojo::mysql::Connection::_encode_lcint(undef);
is $c->{incoming}, pack('C', 251), 'null _encode_lcint';
is $c->_get_int(1), 251, 'null _get_int';
is $c->_chew_lcint, undef, 'null _chew_lcint';
is $c->{incoming}, '', 'null empty after chew';

foreach my $t (0, 1, 10, 100, 250) {
	$c->{incoming} = Mojo::mysql::Connection::_encode_lcint($t);
	is length($c->{incoming}), 1, '1byte length';
	is $c->{incoming}, pack('C', $t), '1byte _encode_int';
	is $c->_get_int(1), $t, '1byte _get_int';
	is $c->_chew_lcint, $t, '1byte _chew_lcint';
	is $c->{incoming}, '', '1byte empty after chew';
}

foreach my $t (251, 1000, 0x1000, 0xffff) {
	$c->{incoming} = Mojo::mysql::Connection::_encode_lcint($t);
	is length($c->{incoming}), 3, '3byte length';
	is $c->{incoming}, pack('Cv', 252, $t), '3byte _encode_lcint';
	is $c->_get_int(1), 252, '3byte header';
	is $c->_chew_lcint, $t, '3byte _chew_lcint';
	is $c->{incoming}, '', 'empty after chew';
}

foreach my $t (0x10000, 0x100000, 0xFFFFFF) {
	$c->{incoming} = Mojo::mysql::Connection::_encode_lcint($t);
	is length($c->{incoming}), 4, '4byte length';
	is $c->{incoming}, substr(pack('CV', 253, $t), 0, 4), '4byte _encode_lcint';
	is $c->_get_int(1), 253, '4byte header';
	is $c->_chew_lcint, $t, '4byte _chew_lcint';
	is $c->{incoming}, '', 'empty after chew';
}

foreach my $t (0x1000000, 17000000, 5000000000) {
	$c->{incoming} = Mojo::mysql::Connection::_encode_lcint($t);
	is length($c->{incoming}), 9, '9byte length';
	is $c->{incoming}, pack('CQ<', 254, $t), '9byte _encode_lcint';
	is $c->_get_int(1), 254, '9byte header';
	is $c->_chew_lcint, $t, '9byte _chew_lcint';
	is $c->{incoming}, '', '9byte empty after chew';
}

foreach my $t (undef, '', 'X' x 10, 'X' x 300, 'X' x 100000, 'X' x 17000000) {
	$c->{incoming} = Mojo::mysql::Connection::_encode_lcstr($t);
	is $c->_chew_lcstr, $t, '_chew_lcstr';
	is $c->{incoming}, '', 'empty after _chew_lcstr';
	$c->{incoming} = Mojo::mysql::Connection::_encode_lcstr($t);
	my $len = $c->_chew_lcint;
	is $c->{incoming}, $t // '', 'str after _chew_lcint';
	is $len // 0, length($t // ''), 'len of str';
}


is $c->_state, 'disconnected', 'state disconnected';
$c->{seq} = 0;

$c->{incoming} = pack('CZ*Va8xvCvvCx10a12xZ*',
	10, 'mysql 5.0', 100, '12345678', 0xFFFF, 33, 0, 0x000F, 21, 'ABCDEFGHIJKL', 'mysql_native_password');
$c->_recv_handshake;
is $c->{incoming}, '', 'empty after recv';
is $c->{protocol_version}, 10, 'protocol_version';
is $c->{server_version}, 'mysql 5.0', 'server_version';
is $c->{connection_id}, 100, 'connection_id';
is $c->{auth_plugin_data}, '12345678ABCDEFGHIJKL', 'auth_plugin_data';
is $c->{capability_flags}, 0xFFFFF, 'capability_flags';
is $c->{character_set}, 33, 'character_set';
is $c->{status_flags}, 0, 'status_flags';
is $c->_state, 'handshake', 'state handshake';

$c->{incoming} = pack('CCCvv', 0, 1, 2, 3, 4);
$c->_recv_ok;
is $c->{incoming}, '', 'empty after recv';
is $c->{affected_rows}, 1, 'affected_rows';
is $c->{last_insert_id}, 2, 'last_insert_id';
is $c->{status_flags}, 3, 'status_flags';
is $c->{warnings_count}, 4, 'warnings_count';
is $c->_state, 'idle', 'state idle';

my ($error, @fields, @result);
my $result_count = 0;

$c->_state('query');
$c->on(error => sub {
	my ($c, $err) = @_;
	$error = $err;
});
$c->on(fields => sub {
	my ($c, $fields) = @_;
	push @fields, $fields;
	$result_count ++;
});
$c->on(result => sub {
	my ($c, $result) = @_;
	push @result, $result;
});

$c->{incoming} = pack('Cva6Z*', 255, 100, '#S0000', 'stupid error');
$c->_recv_ok;
is $c->{incoming}, '', 'empty after recv';
is $c->{error}, 100, 'error';
is $c->{error_state}, '#S0000', 'error_state';
is $c->{error_str}, 'stupid error', 'error_str';
is $c->_state, 'idle', 'state idle on error';

$c->_reset;

$c->{incoming} = pack('C', 1);
$c->_recv_query_responce;
is $c->{incoming}, '', 'empty after recv';
is $c->{field_count}, 1, 'field_count';
is $c->_state, 'field', 'state field';

$c->{incoming} = pack('Ca*Ca*Ca*Ca*Ca*Ca*CvVCvCx2',
	7, 'catalog', 6, 'schema', 5, 'table', 9, 'org_table', 4, 'name', 8, 'org_name', 0x0c,
	33, 10, 0x0f, 12, 13);
$c->_recv_field;
is $c->{incoming}, '', 'empty after recv';

is $c->_state, 'field', 'state field';
is $result_count, 0, 'result_count';

$c->{incoming} = pack('Cvv', 254, 10, 11);
$c->_recv_field; # actualy _recv_eof
is $c->{incoming}, '', 'empty after recv';
is $c->{warnings_count}, 10, 'warnings_count';
is $c->{status_flags}, 11, 'status_flags';
is $result_count, 1, 'result_count';
is $c->_state, 'result', 'state field';

is_deeply \@fields, [[
	{
		catalog => 'catalog',
		schema => 'schema',
		table => 'table',
		org_table => 'org_table',
		name => 'name',
		org_name => 'org_name',
		character_set => 33,
		column_length => 10,
		column_type => 0x0f,
		flags => 12,
		decimals => 13,
	}
	]], 'column_info';


$c->{incoming} = pack('Ca*', 5, 'row 1');
$c->_recv_row;
is $c->{incoming}, '', 'empty after recv';

$c->{incoming} = pack('Ca*', 5, 'row 2');
$c->_recv_row;
is $c->{incoming}, '', 'empty after recv';

$c->{incoming} = pack('Cvv', 254, 0, 0);
$c->_recv_row; # actualy _recv_eof
is $c->{incoming}, '', 'empty after recv';

is_deeply \@result, [ ['row 1'], ['row 2'] ], 'rows';
is $c->_state, 'idle', 'state idle';


$c->_state('disconnected');

done_testing();

