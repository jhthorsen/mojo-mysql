use Mojo::Base -strict;
use Mojo::mysql;
use Test::More;

my %options = (AutoCommit => 1, AutoInactiveDestroy => 1, PrintError => 0, RaiseError => 1);

for my $engine (qw(MariaDB mysql)) {
  for my $class (qw(str Mojo::URL URI::db)) {
    subtest "$engine - $class" => sub {
      plan skip_all => 'URI::db not installed' unless Mojo::mysql::URI;
      my $str   = lc "$engine://user:pass\@localhost:42/test?a=b";
      my $url   = $class eq 'str' ? $str : $class->new($str);
      my $mysql = Mojo::mysql->new($url);
      is $mysql->dsn,      "dbi:${engine}:dbname=test;host=localhost;port=42", 'dsn';
      is $mysql->username, 'user',                                             'username';
      is $mysql->password, 'pass',                                             'password';
      local $options{mysql_enable_utf8} = 1 if $engine eq 'mysql';
      is_deeply $mysql->options, {%options, a => 'b'}, 'options';
    };
  }

  subtest "$engine - ssl" => sub {
    my $str = lc
      "$engine://localhost:42/test?mysql_ssl=1&mysql_ssl_verify=1&mysql_ssl_verify_server_cert=1&mysql_ssl_client_key=key.pem&mysql_ssl_client_cert=crt.pem&mysql_ssl_ca_file=ca.pem";
    my $mysql = Mojo::mysql->new($str);
    is $mysql->dsn,      "dbi:${engine}:dbname=test;host=localhost;port=42", 'dsn';
    is $mysql->username, '',                                                 'username';
    is $mysql->password, '',                                                 'password';
    local $options{mysql_enable_utf8} = 1 if $engine eq 'mysql';
    is_deeply $mysql->options,
      {
      %options,
      mysql_ssl                    => 1,
      mysql_ssl_ca_file            => 'ca.pem',
      mysql_ssl_client_cert        => 'crt.pem',
      mysql_ssl_client_key         => 'key.pem',
      mysql_ssl_verify             => 1,
      mysql_ssl_verify_server_cert => 1,
      },
      'options';
  };
}

subtest 'MariaDB 1.21 is required' => sub {
  plan skip_all => 'MariaDB is installed' if Mojo::mysql::MARIADB;
  my $mysql = Mojo::mysql->new('mariadb://localhost:42/test');
  eval { $mysql->_dequeue };
  like $@, qr/DBD::MariaDB.*is required/, 'error';
};

done_testing;
