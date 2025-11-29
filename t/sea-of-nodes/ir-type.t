# ABOUTME: Unit tests for IR-level type system used by compute()
# ABOUTME: Tests Type base class and is_constant/value interface

use lib 'lib';
use v5.42;
use Test::More;
use Scalar::Util qw(refaddr);

use_ok('Chalk::IR::Type');

subtest 'Type base class interface' => sub {
    my $type = Chalk::IR::Type->new();
    ok($type, 'Can create base Type');
    is($type->is_constant, 0, 'Base type is not constant');
};

use_ok('Chalk::IR::Type::Top');

subtest 'Top type (unknown value)' => sub {
    my $top1 = Chalk::IR::Type::Top->TOP;
    my $top2 = Chalk::IR::Type::Top->TOP;

    ok($top1, 'Can get TOP singleton');
    ok($top1 isa Chalk::IR::Type, 'TOP isa Type');
    is($top1->is_constant, 0, 'TOP is not constant');
    is(refaddr($top1), refaddr($top2), 'TOP is singleton');
};

use_ok('Chalk::IR::Type::Bottom');

subtest 'Bottom type (error state)' => sub {
    my $bot1 = Chalk::IR::Type::Bottom->BOTTOM;
    my $bot2 = Chalk::IR::Type::Bottom->BOTTOM;

    ok($bot1, 'Can get BOTTOM singleton');
    ok($bot1 isa Chalk::IR::Type, 'BOTTOM isa Type');
    is($bot1->is_constant, 0, 'BOTTOM is not constant');
    is(refaddr($bot1), refaddr($bot2), 'BOTTOM is singleton');
};

done_testing();
