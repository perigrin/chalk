#!/usr/bin/env perl
# ABOUTME: Tests for type widening (Int→Float automatic conversion)
# ABOUTME: Verifies integers automatically widen to floats in mixed operations

use 5.42.0;
use utf8;
use Test::More;
use experimental qw(class);

# Load type classes
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Integer;

# ============================================================
# Int→Float widening tests
# ============================================================

subtest 'Integer widen() to Float' => sub {
    my $int = Chalk::IR::Type::Integer->constant(42);
    my $float = Chalk::IR::Type::Float->constant(3.14);

    # Integer should have a widen() method that converts to Float
    can_ok($int, 'widen');

    # widen(Integer, Float) should return Float type
    my $widened = $int->widen($float);
    isa_ok($widened, 'Chalk::IR::Type::Float', 'Integer widens to Float');
    ok($widened->is_constant(), 'widened value is constant');
    is($widened->value, 42.0, 'widened value is 42.0 (float)');
};

subtest 'Integer widen() with FloatTop' => sub {
    my $int = Chalk::IR::Type::Integer->constant(42);
    my $float_top = Chalk::IR::Type::Float->TOP();

    my $widened = $int->widen($float_top);
    isa_ok($widened, 'Chalk::IR::Type::Float', 'Integer widens to Float');
    ok($widened->is_constant(), 'widened constant stays constant');
    is($widened->value, 42.0, 'value is 42.0');
};

subtest 'IntTop widen() to FloatTop' => sub {
    my $int_top = Chalk::IR::Type::Integer->TOP();
    my $float = Chalk::IR::Type::Float->constant(3.14);

    my $widened = $int_top->widen($float);
    isa_ok($widened, 'Chalk::IR::Type::Float', 'IntTop widens to FloatTop');
    ok($widened->is_top(), 'IntTop widens to FloatTop');
};

subtest 'Integer widen() with Integer returns self' => sub {
    my $int1 = Chalk::IR::Type::Integer->constant(42);
    my $int2 = Chalk::IR::Type::Integer->constant(10);

    # widen(Integer, Integer) should return self (no widening needed)
    my $result = $int1->widen($int2);
    is($result, $int1, 'Integer->widen(Integer) returns self');
};

subtest 'Float widen() returns self' => sub {
    my $float1 = Chalk::IR::Type::Float->constant(3.14);
    my $float2 = Chalk::IR::Type::Float->constant(2.72);

    # Float doesn't need widening - should have widen() that returns self
    can_ok($float1, 'widen');
    my $result = $float1->widen($float2);
    is($result, $float1, 'Float->widen(Float) returns self');
};

subtest 'Float widen() with Integer returns self' => sub {
    my $float = Chalk::IR::Type::Float->constant(3.14);
    my $int = Chalk::IR::Type::Integer->constant(42);

    # Float is already wider than Integer
    my $result = $float->widen($int);
    is($result, $float, 'Float->widen(Integer) returns self');
};

# ============================================================
# Mixed type operations using join (which should trigger widening)
# ============================================================

subtest 'join() triggers Int→Float widening' => sub {
    my $int = Chalk::IR::Type::Integer->constant(42);
    my $float = Chalk::IR::Type::Float->constant(3.14);

    # In some type systems, join() might trigger widening
    # But in Sea of Nodes, widening is explicit via widen()
    # This test documents the behavior

    my $result = $int->join($float);
    # Cross-type join should return global Top
    isa_ok($result, 'Chalk::IR::Type::Top', 'join(Int, Float) = global Top without widening');
};

done_testing();
