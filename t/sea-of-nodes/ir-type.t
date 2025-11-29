# ABOUTME: Unit tests for IR-level type system used by compute()
# ABOUTME: Tests Type base class and is_constant/value interface

use lib 'lib';
use v5.42;
use Test::More;

use_ok('Chalk::IR::Type');

subtest 'Type base class interface' => sub {
    my $type = Chalk::IR::Type->new();
    ok($type, 'Can create base Type');
    is($type->is_constant, 0, 'Base type is not constant');
};

done_testing();
