use Mojo::Base -strict;

use Test::More;

plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};
plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!'
  unless eval 'use Test::Pod::Coverage 1.04; 1';

pod_coverage_ok('Mojo::mysql');
pod_coverage_ok('Mojo::mysql::Database', { also_private => ['do'] });
pod_coverage_ok('Mojo::mysql::Migrations');
pod_coverage_ok('Mojo::mysql::Results');
pod_coverage_ok('Mojo::mysql::Transaction');
pod_coverage_ok('Mojo::mysql::Util');
pod_coverage_ok('Mojo::mysql::Connection');

done_testing();
