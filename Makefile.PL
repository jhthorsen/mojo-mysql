use 5.016;
use strict;
use warnings;
use utf8;
use ExtUtils::MakeMaker;

my $GITHUB_URL        = 'https://github.com/jhthorsen/mojo-mysql';
my %WriteMakefileArgs = (
  NAME          => 'Mojo::mysql',
  AUTHOR        => 'Jan Henning Thorsen <jhthorsen@cpan.org>',
  LICENSE       => 'artistic_2',
  ABSTRACT_FROM => 'lib/Mojo/mysql.pm',
  VERSION_FROM  => 'lib/Mojo/mysql.pm',
  TEST_REQUIRES => {'Test::More' => '0.90'},
  PREREQ_PM     => {'DBD::mysql' => '4.050', 'DBI' => '1.643', 'Mojolicious' => '8.03', 'SQL::Abstract' => '1.86'},
  META_MERGE    => {
    'dynamic_config' => 0,
    'meta-spec'      => {version   => 2},
    'no_index'       => {directory => [qw(examples t)]},
    'prereqs'        => {runtime   => {requires => {perl => '5.016'}}},
    'resources'      => {
      bugtracker => {web => "$GITHUB_URL/issues"},
      homepage   => $GITHUB_URL,
      license    => ['http://www.opensource.org/licenses/artistic-license-2.0'],
      repository => {type => 'git', url => "$GITHUB_URL.git", web => $GITHUB_URL},
      x_IRC      => {url  => 'irc://irc.libera.chat/#convos', web => 'https://web.libera.chat/#convos'},
    },
    'x_contributors' => [
      'Adam Hopkins <violapiratejunky@gmail.com>',
      'Alexander Karelas <alex.karelas@gmail.com>',
      'Curt Hochwender <hochwender@centurytel.net>',
      'Dan Book <grinnz@grinnz.com>',
      'Doug Bell <doug@preaction.me>',
      'Florian Heyer <info@heyer-it.de>',
      'Hernan Lopes <hernanlopes@gmail.com>',
      'Jan Henning Thorsen <jhthorsen@cpan.org>',
      'Karl Rune Nilsen <krunen@gmail.com>',
      'Larry Leszczynski <larryl@emailplus.org>',
      'Lucas Tiago de Moraes <lucastiagodemoraes@gmail.com>',
      'Matt S Trout <mst@shadowcat.co.uk>',
      'Mike Magowan <mike@magowan.co.uk>',
      'Mohammad S Anwar <mohammad.anwar@yahoo.com>',
      'Rolf Stöckli <tekki@cpan.org>',
      'Sebastian Riedel <sri@cpan.org>',
      'Svetoslav Naydenov <harry@bix.bg>',
      'Svetoslav Naydenov <harryl@cpan.org>',
      'Tekki <tekki@tekki.ch>',
    ],
  },
  test => {TESTS => (-e 'META.yml' ? 't/*.t' : 't/*.t xt/*.t')},
);

unless (eval { ExtUtils::MakeMaker->VERSION('6.63_03') }) {
  my $test_requires = delete $WriteMakefileArgs{TEST_REQUIRES};
  @{$WriteMakefileArgs{PREREQ_PM}}{keys %$test_requires} = values %$test_requires;
}

WriteMakefile(%WriteMakefileArgs);
