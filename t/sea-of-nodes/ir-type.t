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
    my $top1 = Chalk::IR::Type::Top->top();
    my $top2 = Chalk::IR::Type::Top->top();

    ok($top1, 'Can get top singleton');
    ok($top1 isa Chalk::IR::Type, 'top isa Type');
    is($top1->is_constant, 0, 'top is not constant');
    is(refaddr($top1), refaddr($top2), 'top is singleton');
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

use_ok('Chalk::IR::Type::Integer');

subtest 'TypeInteger (constant value)' => sub {
    my $int42 = Chalk::IR::Type::Integer->constant(42);
    my $int0 = Chalk::IR::Type::Integer->constant(0);

    ok($int42, 'Can create TypeInteger');
    ok($int42 isa Chalk::IR::Type, 'TypeInteger isa Type');
    is($int42->is_constant, 1, 'TypeInteger is constant');
    is($int42->value, 42, 'value() returns stored value');
    is($int0->value, 0, 'value() returns 0 for zero constant');
};

subtest 'TypeInteger TOP (unknown integer)' => sub {
    my $top1 = Chalk::IR::Type::Integer->TOP();
    my $top2 = Chalk::IR::Type::Integer->TOP();

    ok($top1, 'Can get IntTop singleton');
    ok($top1 isa Chalk::IR::Type::Integer, 'IntTop isa TypeInteger');
    is($top1->is_constant, 0, 'IntTop is not constant');
    ok($top1->is_top, 'IntTop is_top returns true');
    ok(!$top1->is_bottom, 'IntTop is_bottom returns false');
    is(refaddr($top1), refaddr($top2), 'IntTop is singleton');
};

subtest 'TypeInteger BOTTOM (integer error state)' => sub {
    my $bot1 = Chalk::IR::Type::Integer->BOTTOM();
    my $bot2 = Chalk::IR::Type::Integer->BOTTOM();

    ok($bot1, 'Can get IntBot singleton');
    ok($bot1 isa Chalk::IR::Type::Integer, 'IntBot isa TypeInteger');
    is($bot1->is_constant, 0, 'IntBot is not constant');
    ok(!$bot1->is_top, 'IntBot is_top returns false');
    ok($bot1->is_bottom, 'IntBot is_bottom returns true');
    is(refaddr($bot1), refaddr($bot2), 'IntBot is singleton');
};

done_testing();
