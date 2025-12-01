# ABOUTME: Unit tests for meet() operation on IR types (lattice intersection)
# ABOUTME: Tests greatest lower bound computation for type inference at merge points

use lib 'lib';
use v5.42;
use Test::More;
use Scalar::Util qw(refaddr);

use_ok('Chalk::IR::Type');
use_ok('Chalk::IR::Type::Top');
use_ok('Chalk::IR::Type::Bottom');
use_ok('Chalk::IR::Type::TypeInteger');
use_ok('Chalk::IR::Type::TypeBool');
use_ok('Chalk::IR::Type::TypeCtrl');

# ============================================================================
# Base Type meet() tests
# ============================================================================

subtest 'Type base class meet()' => sub {
    my $type1 = Chalk::IR::Type->new();
    my $type2 = Chalk::IR::Type->new();

    ok($type1->can('meet'), 'Type has meet() method');

    my $result = $type1->meet($type2);
    ok($result, 'meet() returns a value');
    ok($result isa Chalk::IR::Type, 'meet() returns a Type');
};

# ============================================================================
# Top meet() tests - Top is identity for meet
# ============================================================================

subtest 'Top meet() operations' => sub {
    my $top = Chalk::IR::Type::Top->top();
    my $bot = Chalk::IR::Type::Bottom->BOTTOM;
    my $int5 = Chalk::IR::Type::TypeInteger->constant(5);
    my $true = Chalk::IR::Type::TypeBool->TRUE;

    # Top meet Top = Top
    my $top_meet_top = $top->meet($top);
    is(refaddr($top_meet_top), refaddr($top), 'Top meet Top = Top');

    # Top meet Bottom = Bottom (Bottom absorbs)
    my $top_meet_bot = $top->meet($bot);
    is(refaddr($top_meet_bot), refaddr($bot), 'Top meet Bottom = Bottom');

    # Top meet anything else = that thing (Top is identity)
    my $top_meet_int = $top->meet($int5);
    is(refaddr($top_meet_int), refaddr($int5), 'Top meet TypeInteger = TypeInteger');

    my $top_meet_bool = $top->meet($true);
    is(refaddr($top_meet_bool), refaddr($true), 'Top meet TypeBool = TypeBool');
};

# ============================================================================
# Bottom meet() tests - Bottom absorbs everything
# ============================================================================

subtest 'Bottom meet() operations' => sub {
    my $top = Chalk::IR::Type::Top->top();
    my $bot = Chalk::IR::Type::Bottom->BOTTOM;
    my $int5 = Chalk::IR::Type::TypeInteger->constant(5);
    my $true = Chalk::IR::Type::TypeBool->TRUE;

    # Bottom meet Bottom = Bottom
    my $bot_meet_bot = $bot->meet($bot);
    is(refaddr($bot_meet_bot), refaddr($bot), 'Bottom meet Bottom = Bottom');

    # Bottom meet Top = Bottom
    my $bot_meet_top = $bot->meet($top);
    is(refaddr($bot_meet_top), refaddr($bot), 'Bottom meet Top = Bottom');

    # Bottom meet anything = Bottom (absorbing)
    my $bot_meet_int = $bot->meet($int5);
    is(refaddr($bot_meet_int), refaddr($bot), 'Bottom meet TypeInteger = Bottom');

    my $bot_meet_bool = $bot->meet($true);
    is(refaddr($bot_meet_bool), refaddr($bot), 'Bottom meet TypeBool = Bottom');
};

# ============================================================================
# TypeInteger meet() tests
# ============================================================================

subtest 'TypeInteger meet() with IntTop/IntBot' => sub {
    my $int_top = Chalk::IR::Type::TypeInteger->TOP();
    my $int_bot = Chalk::IR::Type::TypeInteger->BOTTOM();
    my $int5 = Chalk::IR::Type::TypeInteger->constant(5);
    my $int7 = Chalk::IR::Type::TypeInteger->constant(7);
    my $int5_dup = Chalk::IR::Type::TypeInteger->constant(5);

    # IntTop meet IntTop = IntTop
    my $top_meet_top = $int_top->meet($int_top);
    is(refaddr($top_meet_top), refaddr($int_top), 'IntTop meet IntTop = IntTop');

    # IntBot meet anything = IntBot (absorbing)
    my $bot_meet_top = $int_bot->meet($int_top);
    is(refaddr($bot_meet_top), refaddr($int_bot), 'IntBot meet IntTop = IntBot');

    my $bot_meet_const = $int_bot->meet($int5);
    is(refaddr($bot_meet_const), refaddr($int_bot), 'IntBot meet constant = IntBot');

    # anything meet IntBot = IntBot
    my $const_meet_bot = $int5->meet($int_bot);
    is(refaddr($const_meet_bot), refaddr($int_bot), 'constant meet IntBot = IntBot');

    # IntTop is identity for meet
    my $top_meet_const = $int_top->meet($int5);
    is($top_meet_const->value, 5, 'IntTop meet constant(5) = constant(5)');

    my $const_meet_top = $int5->meet($int_top);
    is($const_meet_top->value, 5, 'constant(5) meet IntTop = constant(5)');
};

subtest 'TypeInteger meet() with constants' => sub {
    my $int_top = Chalk::IR::Type::TypeInteger->TOP();
    my $int5 = Chalk::IR::Type::TypeInteger->constant(5);
    my $int7 = Chalk::IR::Type::TypeInteger->constant(7);
    my $int5_dup = Chalk::IR::Type::TypeInteger->constant(5);

    # Same constant values meet = that constant
    my $same_meet = $int5->meet($int5_dup);
    ok($same_meet->is_constant, 'same constants meet is constant');
    is($same_meet->value, 5, 'same constants meet returns same value');

    # Different constants meet = IntTop (we don't know which)
    my $diff_meet = $int5->meet($int7);
    ok($diff_meet->is_top, 'different constants meet = IntTop');
    ok(!$diff_meet->is_constant, 'different constants meet is not constant');
};

# ============================================================================
# TypeBool meet() tests
# ============================================================================

subtest 'TypeBool meet() operations' => sub {
    my $true = Chalk::IR::Type::TypeBool->TRUE;
    my $false = Chalk::IR::Type::TypeBool->FALSE;
    my $top = Chalk::IR::Type::Top->top();
    my $bot = Chalk::IR::Type::Bottom->BOTTOM;

    # Same boolean meets = that boolean
    my $true_meet_true = $true->meet($true);
    is(refaddr($true_meet_true), refaddr($true), 'TRUE meet TRUE = TRUE');

    my $false_meet_false = $false->meet($false);
    is(refaddr($false_meet_false), refaddr($false), 'FALSE meet FALSE = FALSE');

    # Different booleans meet = Top (unknown which)
    my $true_meet_false = $true->meet($false);
    is(refaddr($true_meet_false), refaddr($top), 'TRUE meet FALSE = Top');

    my $false_meet_true = $false->meet($true);
    is(refaddr($false_meet_true), refaddr($top), 'FALSE meet TRUE = Top');

    # TypeBool meet Bottom = Bottom
    my $bool_meet_bot = $true->meet($bot);
    is(refaddr($bool_meet_bot), refaddr($bot), 'TypeBool meet Bottom = Bottom');

    # TypeBool meet Top = TypeBool (Top is identity)
    my $bool_meet_top = $true->meet($top);
    is(refaddr($bool_meet_top), refaddr($true), 'TypeBool meet Top = TypeBool');
};

# ============================================================================
# TypeCtrl meet() tests
# ============================================================================

subtest 'TypeCtrl meet() operations' => sub {
    my $ctrl = Chalk::IR::Type::TypeCtrl->CTRL;
    my $top = Chalk::IR::Type::Top->top();
    my $bot = Chalk::IR::Type::Bottom->BOTTOM;

    # Ctrl meet Ctrl = Ctrl
    my $ctrl_meet_ctrl = $ctrl->meet($ctrl);
    is(refaddr($ctrl_meet_ctrl), refaddr($ctrl), 'CTRL meet CTRL = CTRL');

    # Ctrl meet Top = Ctrl
    my $ctrl_meet_top = $ctrl->meet($top);
    is(refaddr($ctrl_meet_top), refaddr($ctrl), 'CTRL meet Top = CTRL');

    # Ctrl meet Bottom = Bottom
    my $ctrl_meet_bot = $ctrl->meet($bot);
    is(refaddr($ctrl_meet_bot), refaddr($bot), 'CTRL meet Bottom = Bottom');
};

# ============================================================================
# Cross-type meet() tests
# ============================================================================

subtest 'Cross-type meet() operations' => sub {
    my $int5 = Chalk::IR::Type::TypeInteger->constant(5);
    my $true = Chalk::IR::Type::TypeBool->TRUE;
    my $top = Chalk::IR::Type::Top->top();

    # Different types meet = Top (incompatible)
    my $int_meet_bool = $int5->meet($true);
    is(refaddr($int_meet_bool), refaddr($top), 'TypeInteger meet TypeBool = Top');

    my $bool_meet_int = $true->meet($int5);
    is(refaddr($bool_meet_int), refaddr($top), 'TypeBool meet TypeInteger = Top');
};

done_testing();
