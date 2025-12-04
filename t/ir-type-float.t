#!/usr/bin/env perl
# ABOUTME: Tests for TypeFloat lattice operations in IR type system
# ABOUTME: Verifies float constant types, meet/join operations, and Int→Float widening

use 5.42.0;
use utf8;
use Test::More;
use experimental qw(class);

# Load type classes
use Chalk::IR::Type::Float;
use Chalk::IR::Type::Integer;
use Chalk::IR::Type::Top;
use Chalk::IR::Type::Bottom;

# ============================================================
# TypeFloat creation and basic properties
# ============================================================

subtest 'TypeFloat TOP and BOTTOM' => sub {
    my $top = Chalk::IR::Type::Float->TOP();
    my $bottom = Chalk::IR::Type::Float->BOTTOM();

    ok($top->is_top(), 'FloatTop is top');
    ok(!$top->is_bottom(), 'FloatTop is not bottom');
    ok(!$top->is_constant(), 'FloatTop is not constant');

    ok($bottom->is_bottom(), 'FloatBot is bottom');
    ok(!$bottom->is_top(), 'FloatBot is not top');
    ok(!$bottom->is_constant(), 'FloatBot is not constant');

    # Singletons
    is($top, Chalk::IR::Type::Float->TOP(), 'TOP is singleton');
    is($bottom, Chalk::IR::Type::Float->BOTTOM(), 'BOTTOM is singleton');
};

subtest 'TypeFloat constants' => sub {
    my $pi = Chalk::IR::Type::Float->constant(3.14159);
    my $e = Chalk::IR::Type::Float->constant(2.71828);
    my $zero = Chalk::IR::Type::Float->constant(0.0);
    my $neg = Chalk::IR::Type::Float->constant(-1.5);

    ok($pi->is_constant(), '3.14159 is constant');
    ok(!$pi->is_top(), '3.14159 is not top');
    ok(!$pi->is_bottom(), '3.14159 is not bottom');
    is($pi->value, 3.14159, 'value is 3.14159');

    ok($e->is_constant(), '2.71828 is constant');
    is($e->value, 2.71828, 'value is 2.71828');

    ok($zero->is_constant(), '0.0 is constant');
    is($zero->value, 0.0, 'value is 0.0');

    ok($neg->is_constant(), '-1.5 is constant');
    is($neg->value, -1.5, 'value is -1.5');
};

# ============================================================
# meet() tests - Greatest Lower Bound
# ============================================================

subtest 'meet() with global Bottom type' => sub {
    my $float = Chalk::IR::Type::Float->constant(3.14);
    my $global_bot = Chalk::IR::Type::Bottom->BOTTOM();

    is($float->meet($global_bot), $global_bot, 'meet(Float, Bottom) = Bottom');
    is($global_bot->meet($float), $global_bot, 'meet(Bottom, Float) = Bottom');
};

subtest 'meet() with global Top type' => sub {
    my $float = Chalk::IR::Type::Float->constant(3.14);
    my $global_top = Chalk::IR::Type::Top->top();

    is($float->meet($global_top), $float, 'meet(Float, Top) = Float');
};

subtest 'meet() within Float domain' => sub {
    my $float_top = Chalk::IR::Type::Float->TOP();
    my $float_bot = Chalk::IR::Type::Float->BOTTOM();
    my $pi = Chalk::IR::Type::Float->constant(3.14159);
    my $e = Chalk::IR::Type::Float->constant(2.71828);
    my $pi2 = Chalk::IR::Type::Float->constant(3.14159);

    # FloatBot absorbs everything
    is($float_bot->meet($float_top), $float_bot, 'meet(FloatBot, FloatTop) = FloatBot');
    is($float_bot->meet($pi), $float_bot, 'meet(FloatBot, 3.14) = FloatBot');
    is($pi->meet($float_bot), $float_bot, 'meet(3.14, FloatBot) = FloatBot');

    # FloatTop is identity for meet
    is($float_top->meet($pi), $pi, 'meet(FloatTop, 3.14) = 3.14');
    is($pi->meet($float_top), $pi, 'meet(3.14, FloatTop) = 3.14');

    # Two same constants = that constant
    is($pi->meet($pi2), $pi, 'meet(3.14, 3.14) = 3.14');

    # Two different constants = FloatTop (no unique greatest lower bound in floats)
    my $result = $pi->meet($e);
    ok($result->is_top(), 'meet(3.14, 2.72) = FloatTop');
    isa_ok($result, 'Chalk::IR::Type::Float', 'result is TypeFloat');
};

subtest 'meet() cross-type with Integer' => sub {
    my $float = Chalk::IR::Type::Float->constant(3.14);
    my $int = Chalk::IR::Type::Integer->constant(42);

    # Cross-type meet = global Top
    my $result = $float->meet($int);
    isa_ok($result, 'Chalk::IR::Type::Top', 'meet(Float, Integer) = global Top');
};

# ============================================================
# join() tests - Least Upper Bound
# ============================================================

subtest 'join() with global Bottom type' => sub {
    my $float = Chalk::IR::Type::Float->constant(3.14);
    my $global_bot = Chalk::IR::Type::Bottom->BOTTOM();

    is($float->join($global_bot), $float, 'join(Float, Bottom) = Float');
};

subtest 'join() with global Top type' => sub {
    my $float = Chalk::IR::Type::Float->constant(3.14);
    my $global_top = Chalk::IR::Type::Top->top();

    is($float->join($global_top), $global_top, 'join(Float, Top) = Top');
    is($global_top->join($float), $global_top, 'join(Top, Float) = Top');
};

subtest 'join() within Float domain' => sub {
    my $float_top = Chalk::IR::Type::Float->TOP();
    my $float_bot = Chalk::IR::Type::Float->BOTTOM();
    my $pi = Chalk::IR::Type::Float->constant(3.14159);
    my $e = Chalk::IR::Type::Float->constant(2.71828);
    my $pi2 = Chalk::IR::Type::Float->constant(3.14159);

    # FloatBot is identity for join
    is($float_bot->join($float_top), $float_top, 'join(FloatBot, FloatTop) = FloatTop');
    is($float_bot->join($pi), $pi, 'join(FloatBot, 3.14) = 3.14');
    is($pi->join($float_bot), $pi, 'join(3.14, FloatBot) = 3.14');

    # FloatTop absorbs everything
    is($float_top->join($pi), $float_top, 'join(FloatTop, 3.14) = FloatTop');
    is($pi->join($float_top), $float_top, 'join(3.14, FloatTop) = FloatTop');

    # Two same constants = that constant
    is($pi->join($pi2), $pi, 'join(3.14, 3.14) = 3.14');

    # Two different constants = FloatTop (least upper bound)
    my $result = $pi->join($e);
    ok($result->is_top(), 'join(3.14, 2.72) = FloatTop');
    isa_ok($result, 'Chalk::IR::Type::Float', 'result is TypeFloat');
};

subtest 'join() cross-type with Integer' => sub {
    my $float = Chalk::IR::Type::Float->constant(3.14);
    my $int = Chalk::IR::Type::Integer->constant(42);

    # Cross-type join = global Top
    my $result = $float->join($int);
    isa_ok($result, 'Chalk::IR::Type::Top', 'join(Float, Integer) = global Top');
};

# ============================================================
# Lattice properties
# ============================================================

subtest 'meet() commutativity' => sub {
    my $pi = Chalk::IR::Type::Float->constant(3.14);
    my $e = Chalk::IR::Type::Float->constant(2.72);
    my $top = Chalk::IR::Type::Float->TOP();

    is($pi->meet($e)->is_top(), $e->meet($pi)->is_top(), 'meet commutes for constants');
    is($pi->meet($top), $top->meet($pi), 'meet commutes with TOP');
};

subtest 'join() commutativity' => sub {
    my $pi = Chalk::IR::Type::Float->constant(3.14);
    my $e = Chalk::IR::Type::Float->constant(2.72);
    my $top = Chalk::IR::Type::Float->TOP();

    is($pi->join($e)->is_top(), $e->join($pi)->is_top(), 'join commutes for constants');
    is($pi->join($top), $top->join($pi), 'join commutes with TOP');
};

subtest 'meet() idempotence' => sub {
    my $pi = Chalk::IR::Type::Float->constant(3.14);
    my $top = Chalk::IR::Type::Float->TOP();
    my $bot = Chalk::IR::Type::Float->BOTTOM();

    is($pi->meet($pi), $pi, 'meet(3.14, 3.14) = 3.14');
    is($top->meet($top), $top, 'meet(TOP, TOP) = TOP');
    is($bot->meet($bot), $bot, 'meet(BOT, BOT) = BOT');
};

subtest 'join() idempotence' => sub {
    my $pi = Chalk::IR::Type::Float->constant(3.14);
    my $top = Chalk::IR::Type::Float->TOP();
    my $bot = Chalk::IR::Type::Float->BOTTOM();

    is($pi->join($pi), $pi, 'join(3.14, 3.14) = 3.14');
    is($top->join($top), $top, 'join(TOP, TOP) = TOP');
    is($bot->join($bot), $bot, 'join(BOT, BOT) = BOT');
};

done_testing();
