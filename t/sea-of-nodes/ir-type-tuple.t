# ABOUTME: Unit tests for TypeTuple IR type
# ABOUTME: Tests multi-return type for nodes like Start

use lib 'lib';
use v5.42;
use Test::More;
use Scalar::Util qw(refaddr);

use_ok('Chalk::IR::Type::Tuple');
use_ok('Chalk::IR::Type::Ctrl');
use_ok('Chalk::IR::Type::Integer');
use_ok('Chalk::IR::Type::Top');

subtest 'TypeTuple::of() construction' => sub {
    my $ctrl = Chalk::IR::Type::Ctrl->CTRL;
    my $int = Chalk::IR::Type::Integer->constant(42);

    my $tuple = Chalk::IR::Type::Tuple->of($ctrl, $int);

    ok($tuple, 'of() returns a value');
    ok($tuple isa Chalk::IR::Type::Tuple, 'of() returns TypeTuple');
};

subtest 'TypeTuple at() extraction' => sub {
    my $ctrl = Chalk::IR::Type::Ctrl->CTRL;
    my $int = Chalk::IR::Type::Integer->constant(42);

    my $tuple = Chalk::IR::Type::Tuple->of($ctrl, $int);

    is(refaddr($tuple->at(0)), refaddr($ctrl), 'at(0) returns first element');
    is(refaddr($tuple->at(1)), refaddr($int), 'at(1) returns second element');
};

subtest 'TypeTuple is_constant when all elements constant' => sub {
    my $ctrl = Chalk::IR::Type::Ctrl->CTRL;
    my $int = Chalk::IR::Type::Integer->constant(42);

    my $tuple = Chalk::IR::Type::Tuple->of($ctrl, $int);

    ok($tuple->is_constant, 'Tuple of constants is constant');
};

subtest 'TypeTuple not constant when any element non-constant' => sub {
    my $ctrl = Chalk::IR::Type::Ctrl->CTRL;
    my $top = Chalk::IR::Type::Top->top;

    my $tuple = Chalk::IR::Type::Tuple->of($ctrl, $top);

    ok(!$tuple->is_constant, 'Tuple with Top element is not constant');
};

subtest 'TypeTuple value() returns array of values' => sub {
    my $ctrl = Chalk::IR::Type::Ctrl->CTRL;
    my $int = Chalk::IR::Type::Integer->constant(42);

    my $tuple = Chalk::IR::Type::Tuple->of($ctrl, $int);

    my $values = $tuple->value;
    ok(ref($values) eq 'ARRAY', 'value() returns arrayref');
    is(scalar(@$values), 2, 'value() has 2 elements');
    ok(!defined($values->[0]), 'First value is undef (ctrl)');
    is($values->[1], 42, 'Second value is 42');
};

subtest 'TypeTuple types() accessor' => sub {
    my $ctrl = Chalk::IR::Type::Ctrl->CTRL;
    my $int = Chalk::IR::Type::Integer->constant(42);

    my $tuple = Chalk::IR::Type::Tuple->of($ctrl, $int);

    my $types = $tuple->types;
    ok(ref($types) eq 'ARRAY', 'types() returns arrayref');
    is(scalar(@$types), 2, 'types() has 2 elements');
};

subtest 'TypeTuple inherits from Chalk::IR::Type' => sub {
    my $tuple = Chalk::IR::Type::Tuple->of(
        Chalk::IR::Type::Ctrl->CTRL
    );
    ok($tuple isa Chalk::IR::Type, 'TypeTuple inherits from Type');
};

done_testing();
