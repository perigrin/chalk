# ABOUTME: Tests Precedence semiring for operator-level disambiguation.
# ABOUTME: Validates operator lookup, precedence nesting, associativity, and is_zero filtering.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;

# ========================================================================
# PrecedenceTable tests
# ========================================================================

# Test 1: Table returns expected structure
{
    my @table = Chalk::Grammar::Perl::PrecedenceTable::get_table();
    ok(scalar @table > 0, 'precedence table has entries');
    is($table[0]->{assoc}, 'right', 'level 0 is right-associative (**)')
}

# Test 2: ** is at level 0
{
    my @table = Chalk::Grammar::Perl::PrecedenceTable::get_table();
    ok((grep { $_ eq '**' } $table[0]->{ops}->@*), '** is at level 0');
}

# Test 3: + and - are at level 3
{
    my @table = Chalk::Grammar::Perl::PrecedenceTable::get_table();
    ok((grep { $_ eq '+' } $table[3]->{ops}->@*), '+ is at level 3');
    ok((grep { $_ eq '-' } $table[3]->{ops}->@*), '- is at level 3');
}

# Test 4: * is at level 2 (higher precedence than +)
{
    my @table = Chalk::Grammar::Perl::PrecedenceTable::get_table();
    ok((grep { $_ eq '*' } $table[2]->{ops}->@*), '* is at level 2');
}

# Test 5: && and || are at different levels
{
    my @table = Chalk::Grammar::Perl::PrecedenceTable::get_table();
    ok((grep { $_ eq '&&' } $table[10]->{ops}->@*), '&& is at level 10');
    ok((grep { $_ eq '||' } $table[11]->{ops}->@*), '|| is at level 11');
}

# Test 6: 'and', 'or' are lowest binary precedence (level 13)
{
    my @table = Chalk::Grammar::Perl::PrecedenceTable::get_table();
    ok((grep { $_ eq 'and' } $table[13]->{ops}->@*), 'and is at level 13');
    ok((grep { $_ eq 'or' } $table[13]->{ops}->@*), 'or is at level 13');
}

# ========================================================================
# Precedence semiring: basic operations
# ========================================================================

my $prec = Chalk::Bootstrap::Semiring::Precedence->new(
    lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
);

# Test 7: zero and one
{
    my $z = $prec->zero();
    my $o = $prec->one();
    ok($prec->is_zero($z), 'zero is zero');
    ok(!$prec->is_zero($o), 'one is not zero');
}

# Test 8: multiply of two ones is one
{
    my $result = $prec->multiply($prec->one(), $prec->one());
    ok(!$prec->is_zero($result), 'multiply(one, one) is not zero');
}

# Test 9: multiply with zero propagates zero
{
    my $result = $prec->multiply($prec->zero(), $prec->one());
    ok($prec->is_zero($result), 'multiply(zero, one) is zero');

    my $result2 = $prec->multiply($prec->one(), $prec->zero());
    ok($prec->is_zero($result2), 'multiply(one, zero) is zero');
}

# Test 10: add returns first non-zero
{
    my $result = $prec->add($prec->one(), $prec->one());
    ok(!$prec->is_zero($result), 'add(one, one) is not zero');

    my $result2 = $prec->add($prec->zero(), $prec->one());
    ok(!$prec->is_zero($result2), 'add(zero, one) is not zero');

    my $result3 = $prec->add($prec->zero(), $prec->zero());
    ok($prec->is_zero($result3), 'add(zero, zero) is zero');
}

# ========================================================================
# Precedence semiring: on_scan with operator detection
# ========================================================================

# Helper: build a mock item with rule and value
my sub make_item($rule_name, $value, $dot = 0, $origin = 0) {
    my $rule = Chalk::Grammar::Rule->new(
        name        => $rule_name,
        expressions => [[]],
    );
    return {
        rule   => $rule,
        dot    => $dot,
        origin => $origin,
        value  => $value,
    };
}

# Test 11: on_scan with non-operator text returns non-zero value
{
    my $item = make_item('Identifier', $prec->one());
    my $result = $prec->on_scan($item, 0, 0, 'foo');
    ok(defined $result, 'on_scan with identifier returns defined value');
    ok(!$prec->is_zero($result), 'on_scan with identifier is not zero');
}

# Test 12: on_scan with operator text in BinaryOp rule tags the value
{
    my $item = make_item('BinaryOp', $prec->one());
    my $result = $prec->on_scan($item, 0, 0, '+');
    ok(defined $result, 'on_scan with + in BinaryOp returns defined value');
    ok(!$prec->is_zero($result), 'on_scan with + in BinaryOp is not zero');
}

# Test 13: on_scan with zero item value returns undef (propagates zero)
{
    my $item = make_item('BinaryOp', $prec->zero());
    my $result = $prec->on_scan($item, 0, 0, '+');
    ok($prec->is_zero($result), 'on_scan with zero item value returns zero');
}

# ========================================================================
# Precedence semiring: on_complete
# ========================================================================

# Test 14: on_complete returns value unchanged for non-expression rules
{
    my $item = make_item('Identifier', $prec->one());
    my $result = $prec->on_complete($item, 0, 5);
    ok(defined $result, 'on_complete for Identifier returns value');
    ok(!$prec->is_zero($result), 'on_complete for Identifier is not zero');
}

# Test 15: on_complete for BinaryOp marks the operator as passive
{
    # Simulate scanning an operator then completing BinaryOp
    my $item = make_item('BinaryOp', $prec->one());
    my $scanned = $prec->on_scan($item, 0, 0, '+');
    my $completed_item = make_item('BinaryOp', $scanned);
    my $result = $prec->on_complete($completed_item, 0, 1);
    ok(defined $result, 'on_complete for BinaryOp returns value');
    ok(!$prec->is_zero($result), 'on_complete for BinaryOp is not zero');
}

# ========================================================================
# Precedence semiring: precedence validation via multiply
# ========================================================================

# Test 16: Higher-precedence child inside lower-precedence parent is valid
# e.g. a + (b * c) — * (level 2) inside + (level 3) is OK
# Simulates the Earley flow: the parent BinaryExpression has accumulated
# the + operator's level via on_scan/on_complete (without is_operator since
# BinaryExpression's on_complete strips it). The child is a completed
# BinaryExpression with * level, also without is_operator.
{
    # Parent context: BinaryExpression completed with + (level 3)
    my $parent_value = { valid => true, op => '+', level => 3, assoc => 'left' };

    # Child: completed BinaryExpression with * (level 2) — Expression pass-through
    my $child_value = { valid => true, op => '*', level => 2, assoc => 'left' };

    # Parent + contains child * — valid (child has higher precedence)
    my $result = $prec->multiply($parent_value, $child_value);
    ok(!$prec->is_zero($result), '* (level 2) inside + (level 3) is valid');
}

# Test 17: Lower-precedence child inside higher-precedence parent is invalid
# e.g. a * (b + c) without parens — + (level 3) inside * (level 2) should be rejected
{
    # Parent context: BinaryExpression completed with * (level 2)
    my $parent_value = { valid => true, op => '*', level => 2, assoc => 'left' };

    # Child: completed BinaryExpression with + (level 3) — Expression pass-through
    my $child_value = { valid => true, op => '+', level => 3, assoc => 'left' };

    # Parent * contains child + — invalid (child has lower precedence)
    my $result = $prec->multiply($parent_value, $child_value);
    ok($prec->is_zero($result), '+ (level 3) inside * (level 2) is invalid');
}

# Test 18: Same-precedence left-associative associativity enforcement
# e.g. a + b + c: (a + b) + c is valid, a + (b + c) is invalid for left-assoc
{
    # Simulates completed BinaryExpression values (no is_operator flag)
    my $inner_value = { valid => true, op => '+', level => 3, assoc => 'left' };
    my $outer_value = { valid => true, op => '+', level => 3, assoc => 'left' };

    # Left-assoc: same-level right operand (inner inside outer) is INVALID.
    # This prevents `a + (b + c)` grouping for left-associative operators.
    # The right operand `b + c` as a BinaryExpression has the same level as
    # the outer `+`, so it must be rejected.
    my $right_result = $prec->multiply($outer_value, $inner_value);
    ok($prec->is_zero($right_result),
        'left-assoc: same-level right operand is invalid (prevents right-grouping)');

    # Left-assoc: same-level left operand is valid (via is_operator path).
    # The left operand `a + b` multiplies with the BinOp `+` (is_operator),
    # and the existing check allows same-level left operands for left-assoc.
    my $operator_val = { valid => true, op => '+', level => 3, assoc => 'left', is_operator => true };
    my $left_result = $prec->multiply($inner_value, $operator_val);
    ok(!$prec->is_zero($left_result),
        'left-assoc: same-level left operand with operator is valid');
}

# Test 19: non-associative operators at same level cannot nest
{
    # Look up isa's level from the precedence table
    my $isa_info = Chalk::Grammar::Perl::PrecedenceTable::lookup('isa');
    my $isa_level = $isa_info->{level};
    my $parent_value = { valid => true, op => 'isa', level => $isa_level, assoc => 'nonassoc' };
    my $child_value  = { valid => true, op => 'isa', level => $isa_level, assoc => 'nonassoc' };

    my $result = $prec->multiply($parent_value, $child_value);
    ok($prec->is_zero($result), 'nonassoc: isa inside isa is invalid');
}

# Test 20: right-associative operators nest on the right
# e.g. a ** b ** c: a ** (b ** c) is valid
{
    # Simulates completed BinaryExpression values (no is_operator flag)
    my $pow_value1 = { valid => true, op => '**', level => 0, assoc => 'right' };
    my $pow_value2 = { valid => true, op => '**', level => 0, assoc => 'right' };

    # Right-assoc: same-level right operand is valid (right-grouping is correct)
    # This allows `$b ** $c` as right operand of `$a ** ...`
    my $result = $prec->multiply($pow_value1, $pow_value2);
    ok(!$prec->is_zero($result), 'right-assoc: ** inside ** is valid');

    # Right-assoc: same-level left operand via is_operator is INVALID.
    # `($a ** $b) ** $c` is invalid — rejects left-grouping for right-assoc.
    my $pow_op = { valid => true, op => '**', level => 0, assoc => 'right', is_operator => true };
    my $left_reject = $prec->multiply($pow_value1, $pow_op);
    ok($prec->is_zero($left_reject),
        'right-assoc: same-level left operand with operator is invalid (prevents left-grouping)');
}

# ========================================================================
# Precedence semiring: ParenExpr resets precedence context
# ========================================================================

# Test 21: on_complete for ParenExpr clears operator info
{
    # Start with an operator-bearing value (simulating BinaryExpression inside parens)
    my $op_value = { valid => true, op => '+', level => 3, assoc => 'left' };

    # Wrap in ParenExpr — on_complete should clear operator info
    my $paren_item = make_item('ParenExpr', $op_value);
    my $paren_result = $prec->on_complete($paren_item, 0, 3);

    # After ParenExpr, the value should be "clean" — no operator restriction
    # So multiplying with a higher-precedence parent (* level 2) should be valid
    my $star_context = { valid => true, op => '*', level => 2, assoc => 'left' };

    my $result = $prec->multiply($star_context, $paren_result);
    ok(!$prec->is_zero($result),
        'parenthesized + inside * is valid (parens reset precedence)');
}

# ========================================================================
# Precedence semiring: Expression-type operators
# ========================================================================

# Test 22: UnaryExpression has higher precedence than BinaryExpression
{
    my $unary_item = make_item('UnaryExpression', $prec->one());
    my $unary_result = $prec->on_complete($unary_item, 0, 2);

    # Binary context with + (level 3)
    my $binary_context = { valid => true, op => '+', level => 3, assoc => 'left' };

    # Unary inside binary is valid (unary level=-1, binary level=3: -1 < 3)
    my $result = $prec->multiply($binary_context, $unary_result);
    ok(!$prec->is_zero($result), 'unary inside binary is valid');
}

# Test 23: AssignmentExpression has lower precedence than BinaryExpression
{
    my $assign_item = make_item('AssignmentExpression', $prec->one());
    my $assign_result = $prec->on_complete($assign_item, 0, 5);

    # Binary context with + (level 3)
    my $binary_context = { valid => true, op => '+', level => 3, assoc => 'left' };

    # Assignment inside binary is invalid (assign level=101, binary level=3: 101 > 3)
    my $result = $prec->multiply($binary_context, $assign_result);
    ok($prec->is_zero($result),
        'assignment inside binary is invalid (lower precedence)');
}

# ========================================================================
# Precedence semiring: is_operator validation in multiply
# ========================================================================

# Test: operator check rejects left operand with lower precedence
# Simulates ($a && $b) =~ /x/ — the BinaryExpression for =~ has accumulated
# left-Expression level=10 (from &&). When BinaryOp =~ (level=1) completes
# with is_operator, multiply checks 10 > 1 and rejects.
{
    my $left_context = { valid => true, op => '&&', level => 10, assoc => 'left' };
    my $bind_op = { valid => true, op => '=~', level => 1, assoc => 'left', is_operator => true };
    my $result = $prec->multiply($left_context, $bind_op);
    ok($prec->is_zero($result),
        'is_operator: left level=10 (&&) > op level=1 (=~) is rejected');
}

# Test: operator check accepts left operand with higher precedence
# Simulates ($a =~ /x/) && $b — left-Expression level=1 (from =~),
# operator && (level=10). 1 <= 10 so it's valid.
{
    my $left_context = { valid => true, op => '=~', level => 1, assoc => 'left' };
    my $and_op = { valid => true, op => '&&', level => 10, assoc => 'left', is_operator => true };
    my $result = $prec->multiply($left_context, $and_op);
    ok(!$prec->is_zero($result),
        'is_operator: left level=1 (=~) <= op level=10 (&&) is valid');
}

# Test: operator check with no left level is valid (first operator in chain)
{
    my $left_context = { valid => true };
    my $and_op = { valid => true, op => '&&', level => 10, assoc => 'left', is_operator => true };
    my $result = $prec->multiply($left_context, $and_op);
    ok(!$prec->is_zero($result),
        'is_operator: no left level + operator is valid (first operator)');
}

# ========================================================================
# Precedence semiring: unknown operators are transparent
# ========================================================================

# Test 24: Scanning non-operator text in non-BinaryOp context is transparent
{
    my $item = make_item('Identifier', $prec->one());
    my $result = $prec->on_scan($item, 0, 0, 'my_var');
    ok(!$prec->is_zero($result), 'non-operator scan in non-BinaryOp is transparent');
}

# ========================================================================
# selects_alternative: cross-semiring disambiguation
# ========================================================================

# Test 25: selects_alternative prefers value with defined level
{
    my $with_level = { valid => true, level => 5, op => '.', assoc => 'left' };
    my $no_level   = { valid => true };

    is($prec->selects_alternative($with_level, $no_level), 'left',
        'selects_alternative prefers left when it has level');
    is($prec->selects_alternative($no_level, $with_level), 'right',
        'selects_alternative prefers right when it has level');
}

# Test 26: selects_alternative prefers higher level (lower precedence = more constraining)
{
    my $binexpr_dot  = { valid => true, level => 5, op => '.', assoc => 'left' };
    my $postfix_expr = { valid => true, level => -2, op => undef, assoc => undef };

    is($prec->selects_alternative($binexpr_dot, $postfix_expr), 'left',
        'selects_alternative prefers BinaryExpr(.) over PostfixExpr');
    is($prec->selects_alternative($postfix_expr, $binexpr_dot), 'right',
        'selects_alternative prefers BinaryExpr(.) over PostfixExpr (reversed)');
}

# Test 27: selects_alternative returns undef when neither has level
{
    my $a = { valid => true };
    my $b = { valid => true };

    is($prec->selects_alternative($a, $b), undef,
        'selects_alternative returns undef when both lack levels');
}

# Test 28: selects_alternative returns undef when same level
{
    my $a = { valid => true, level => 5, op => '.', assoc => 'left' };
    my $b = { valid => true, level => 5, op => '.', assoc => 'left' };

    is($prec->selects_alternative($a, $b), undef,
        'selects_alternative returns undef when same level');
}

# Test 29: selects_alternative returns undef when either is zero
{
    my $z = $prec->zero();
    my $v = { valid => true, level => 5 };

    is($prec->selects_alternative($z, $v), undef,
        'selects_alternative returns undef when left is zero');
    is($prec->selects_alternative($v, $z), undef,
        'selects_alternative returns undef when right is zero');
}

done_testing();
