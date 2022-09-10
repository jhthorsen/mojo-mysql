use strict;
use warnings;
use Test::More;
use File::Find;

plan skip_all => 'HARNESS_PERL_SWITCHES =~ /Devel::Cover/' if +($ENV{HARNESS_PERL_SWITCHES} || '') =~ /Devel::Cover/;

for (qw(
  Test::CPAN::Changes::changes_file_ok+VERSION!4
  Test::Pod::Coverage::pod_coverage_ok+VERSION!1
  Test::Pod::pod_file_ok+VERSION!1
  Test::Spelling::pod_file_spelling_ok+has_working_spellchecker!1
))
{
  my ($fqn, $module, $sub, $check, $skip_n) = /^((.*)::(\w+))\+(\w+)!(\d+)$/;
  next if eval "use $module;$module->$check";
  no strict qw(refs);
  *$fqn = sub {
  SKIP: { skip "$sub(@_) ($module is required)", $skip_n }
  };
}

my @files;
find({wanted => sub { /\.pm$/ and push @files, $File::Find::name }, no_chdir => 1}, -e 'blib' ? 'blib' : 'lib');
plan tests => @files * 4 + 4;

Test::Spelling::add_stopwords(<DATA>)
  if Test::Spelling->can('has_working_spellchecker') && Test::Spelling->has_working_spellchecker;

for my $file (@files) {
  my $module = $file;
  $module =~ s,\.pm$,,;
  $module =~ s,.*/?lib/,,;
  $module =~ s,/,::,g;
  ok eval "use $module; 1", "use $module" or diag $@;
  Test::Pod::pod_file_ok($file);
  Test::Pod::Coverage::pod_coverage_ok($module, {also_private => [qr/^[A-Z_]+$/]});
  Test::Spelling::pod_file_spelling_ok($file);
}

Test::CPAN::Changes::changes_file_ok();

__DATA__
Anwar
Async
DBD
DDL
DML
Florian
Henning
Hernan
Heyer
Hochwender
Karelas
Leszczynski
Magowan
Mojolicious
Moraes
Naydenov
Nilsen
Riedel
Rolf
Stöckli
Svetoslav
Tekki
Thorsen
Tiago
dbh
de
dsn
errstr
mariadb
pubsub
puke
schemas
sql
sth
unicode
unlisten
