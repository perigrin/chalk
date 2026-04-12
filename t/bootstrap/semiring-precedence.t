# ABOUTME: Tests Precedence semiring for operator-level disambiguation.
# ABOUTME: Validates operator lookup, precedence nesting, associativity, and is_zero filtering.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Context;

# Helper: build an annotated scan Context (as Earley would create it)
sub make_scan_ctx($rule_name, $matched_text, $is_predicted_hash = {}) {
    return Chalk::Bootstrap::Context->new(
        focus       => $matched_text,
        position    => 0,
        annotations => {
            scan      => true,
            rule_name => $rule_name,
            alt_idx   => 0,
            predicted => $is_predicted_hash,
        },
    );
}

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

# Test 6: 'and' is at level 13, 'or' at level 14 (matching perlop)
{
    my @table = Chalk::Grammar::Perl::PrecedenceTable::get_table();
    ok((grep { $_ eq 'and' } $table[13]->{ops}->@*), 'and is at level 13');
    ok((grep { $_ eq 'or' } $table[14]->{ops}->@*), 'or is at level 14');
}

# Test 6b: 'isa' is at level 5 (above comparisons, matching perlop)
{
    my @table = Chalk::Grammar::Perl::PrecedenceTable::get_table();
    ok((grep { $_ eq 'isa' } $table[5]->{ops}->@*), 'isa is at level 5');
    is($table[5]->{assoc}, 'nonassoc', 'isa level is nonassoc');
}

# Test 6c: Comparisons at level 6 are chained (matching perlop)
{
    my @table = Chalk::Grammar::Perl::PrecedenceTable::get_table();
    ok((grep { $_ eq '<' } $table[6]->{ops}->@*), '< is at level 6');
    ok((grep { $_ eq '>=' } $table[6]->{ops}->@*), '>= is at level 6');
    is($table[6]->{assoc}, 'chained', 'comparison level is chained');
}

# Test 6d: Equality at level 7 is nonassoc (matching perlop)
{
    my @table = Chalk::Grammar::Perl::PrecedenceTable::get_table();
    ok((grep { $_ eq '==' } $table[7]->{ops}->@*), '== is at level 7');
    ok((grep { $_ eq 'ne' } $table[7]->{ops}->@*), 'ne is at level 7');
    is($table[7]->{assoc}, 'nonassoc', 'equality level is nonassoc');
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

# Test 10: add returns single-element arrayref; unwrap to check value
{
    my $result = $prec->add($prec->one(), $prec->one());
    ok(!$prec->is_zero($result->[0]), 'add(one, one) winner is not zero');

    my $result2 = $prec->add($prec->zero(), $prec->one());
    ok(!$prec->is_zero($result2->[0]), 'add(zero, one) winner is not zero');

    my $result3 = $prec->add($prec->zero(), $prec->zero());
    ok($prec->is_zero($result3->[0]), 'add(zero, zero) winner is zero');
}

# ========================================================================
# Precedence semiring: multiply with scan Context (operator detection)
# Scan events arrive as multiply($left, $scan_ctx) in the unified protocol.
# ========================================================================

{
    use Chalk::Bootstrap::Context;
    my $make_scan = sub ($rule, $text) {
        return Chalk::Bootstrap::Context->new(
            focus       => $text,
            position    => 0,
            annotations => { scan => true, rule_name => $rule, alt_idx => 0, predicted => {} },
        );
    };

    # Test 11: multiply with non-operator scan returns non-zero value
    my $result = $prec->multiply($prec->one(), $make_scan->('Identifier', 'foo'));
    ok(defined $result, 'multiply with identifier scan returns defined value');
    ok(!$prec->is_zero($result), 'multiply with identifier scan is not zero');

    # Test 12: multiply with operator scan in BinaryOp rule tags the value
    my $op_result = $prec->multiply($prec->one(), $make_scan->('BinaryOp', '+'));
    ok(defined $op_result, 'multiply with + BinaryOp scan returns defined value');
    ok(!$prec->is_zero($op_result), 'multiply with + BinaryOp scan is not zero');

    # Test 13: multiply with zero left propagates zero
    my $zero_result = $prec->multiply($prec->zero(), $make_scan->('BinaryOp', '+'));
    ok($prec->is_zero($zero_result), 'multiply with zero left propagates zero');
}

# ========================================================================
# Precedence semiring: on_complete
# ========================================================================

# Test 14: on_complete returns value unchanged for non-expression rules
{
    my $result = $prec->on_complete($prec->one(), 'Identifier', 0, 5, 0);
    ok(defined $result, 'on_complete for Identifier returns value');
    ok(!$prec->is_zero($result), 'on_complete for Identifier is not zero');
}

# Test 15: on_complete for BinaryOp marks the operator as passive
{
    # Simulate scanning an operator then completing BinaryOp
    # (Using multiply with scan Context instead of on_scan)
    use Chalk::Bootstrap::Context;
    my $scan_ctx = Chalk::Bootstrap::Context->new(
        focus       => '+',
        position    => 0,
        annotations => { scan => true, rule_name => 'BinaryOp', alt_idx => 0, predicted => {} },
    );
    my $scanned = $prec->multiply($prec->one(), $scan_ctx);
    my $result = $prec->on_complete($scanned, 'BinaryOp', 0, 1, 0);
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
    my $paren_result = $prec->on_complete($op_value, 'ParenExpr', 0, 3, 0);

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
    my $unary_result = $prec->on_complete($prec->one(), 'UnaryExpression', 0, 2, 0);

    # Binary context with + (level 3)
    my $binary_context = { valid => true, op => '+', level => 3, assoc => 'left' };

    # Unary inside binary is valid (unary level=-1, binary level=3: -1 < 3)
    my $result = $prec->multiply($binary_context, $unary_result);
    ok(!$prec->is_zero($result), 'unary inside binary is valid');
}

# Test 23: AssignmentExpression has lower precedence than BinaryExpression
{
    my $assign_result = $prec->on_complete($prec->one(), 'AssignmentExpression', 0, 5, 0);

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
    my $result = $prec->multiply($prec->one(), make_scan_ctx('Identifier', 'my_var'));
    ok(!$prec->is_zero($result), 'non-operator scan in non-BinaryOp is transparent');
}

# Note: selects_alternative() was removed. Disambiguation is now handled
# via the identity-detection protocol in FilterComposite._filter_compare():
# add() returns [$winner] and FilterComposite detects preference by comparing
# refaddr of the result with the inputs.

# ========================================================================
# Precedence semiring: AssignOp scan sets is_operator for disambiguation
# ========================================================================

# Test 30: AssignOp //= gets level 101, right-assoc, and is_operator via multiply with scan Context
{
    my $assign_scan = $prec->multiply($prec->one(), make_scan_ctx('AssignOp', '//='));
    ok($assign_scan->{is_operator}, 'AssignOp //= sets is_operator');
    is($assign_scan->{level}, 101, 'AssignOp //= has level 101');
    is($assign_scan->{assoc}, 'right', 'AssignOp //= has right assoc');
}

# Test 31: AssignOp = also gets is_operator
{
    my $assign_scan = $prec->multiply($prec->one(), make_scan_ctx('AssignOp', '='));
    ok($assign_scan->{is_operator}, 'AssignOp = sets is_operator');
    is($assign_scan->{level}, 101, 'AssignOp = has level 101');
    is($assign_scan->{assoc}, 'right', 'AssignOp = has right assoc');
}

# Test 32: Chained assignment right-associativity rejection during scan multiply
# `(my $x = $y) //= 1` is invalid — the left operand of //= is an
# AssignmentExpression (level 101), same level as //=.
# multiply rejects this when the existing left carries level=101.
{
    my $left_assign = { valid => true, level => 101, assoc => 'right' };
    my $result = $prec->multiply($left_assign, make_scan_ctx('AssignOp', '//='));
    ok($prec->is_zero($result),
        'multiply rejects AssignOp //= when left operand is AssignmentExpression (level=101)');
}

# Test 33: Valid chained assignment: right-nesting is allowed
# `my $x = ($y //= 1)` — the right operand of = is an AssignmentExpression,
# which is fine because right-assoc allows same-level right operands.
{
    my $outer_op = { valid => true, op => '=', level => 101, assoc => 'right' };
    my $inner_assign = { valid => true, op => '//=', level => 101, assoc => 'right' };
    my $result = $prec->multiply($outer_op, $inner_assign);
    ok(!$prec->is_zero($result),
        'assignment as right operand of same-level right-assoc = is valid');
}

# ========================================================================
# Hash-consing: zero and one are singletons
# ========================================================================

# Test 34: zero() always returns the same object
{
    my $z1 = $prec->zero();
    my $z2 = $prec->zero();
    is(refaddr($z1), refaddr($z2), 'zero() returns the same object each time');
}

# Test 35: one() always returns the same object
{
    my $o1 = $prec->one();
    my $o2 = $prec->one();
    is(refaddr($o1), refaddr($o2), 'one() returns the same object each time');
}

# Test 36: zero and one are different objects
{
    my $z = $prec->zero();
    my $o = $prec->one();
    isnt(refaddr($z), refaddr($o), 'zero() and one() are distinct objects');
}

# ========================================================================
# Hash-consing: multiply returns interned objects
# ========================================================================

# Test 37: multiply(one, one) returns same object on repeat calls
{
    my $r1 = $prec->multiply($prec->one(), $prec->one());
    my $r2 = $prec->multiply($prec->one(), $prec->one());
    is(refaddr($r1), refaddr($r2), 'multiply(one,one) returns the same object each time');
}

# Test 38: multiply(zero, one) returns zero singleton
{
    my $result = $prec->multiply($prec->zero(), $prec->one());
    is(refaddr($result), refaddr($prec->zero()), 'multiply(zero,one) returns zero singleton');
}

# Test 39: multiply with same operator inputs yields same object
{
    my $left  = { valid => true, op => '+', level => 3, assoc => 'left' };
    my $right = { valid => true, op => '+', level => 3, assoc => 'left' };
    my $r1    = $prec->multiply($prec->one(), $left);
    my $r2    = $prec->multiply($prec->one(), $right);
    is(refaddr($r1), refaddr($r2),
        'multiply with same (level,assoc) inputs yields same interned object');
}

# Test 40: multiply zero-path returns zero singleton
{
    my $parent = { valid => true, op => '*', level => 2, assoc => 'left' };
    my $child  = { valid => true, op => '+', level => 3, assoc => 'left' };
    my $result = $prec->multiply($parent, $child);
    ok($prec->is_zero($result), 'rejected multiply still returns zero');
    is(refaddr($result), refaddr($prec->zero()), 'rejected multiply returns zero singleton');
}

# ========================================================================
# Hash-consing: scan multiply returns interned objects
# ========================================================================

# Test 41: multiply with same operator in BinaryOp yields same interned object
{
    my $r1 = $prec->multiply($prec->one(), make_scan_ctx('BinaryOp', '+'));
    my $r2 = $prec->multiply($prec->one(), make_scan_ctx('BinaryOp', '+'));
    is(refaddr($r1), refaddr($r2),
        'multiply with same operator scan returns same interned object');
}

# Test 42: multiply with zero left and scan returns zero singleton
{
    my $result = $prec->multiply($prec->zero(), make_scan_ctx('BinaryOp', '+'));
    is(refaddr($result), refaddr($prec->zero()),
        'multiply with zero left and scan returns zero singleton');
}

# Test 43: multiply with non-operator context scan returns interned one
{
    my $r1 = $prec->multiply($prec->one(), make_scan_ctx('Identifier', 'foo'));
    my $r2 = $prec->multiply($prec->one(), make_scan_ctx('Identifier', 'bar'));
    is(refaddr($r1), refaddr($r2),
        'multiply in non-operator context returns same interned object for same input value');
}

# ========================================================================
# Hash-consing: on_complete returns interned objects
# ========================================================================

# Test 44: on_complete for ParenExpr always returns same (one) object
{
    my $op_value = { valid => true, op => '+', level => 3, assoc => 'left' };
    my $r1 = $prec->on_complete($op_value, 'ParenExpr', 0, 0, 0);
    my $r2 = $prec->on_complete({ valid => true, op => '-', level => 5, assoc => 'left' }, 'ParenExpr', 0, 0, 0);
    is(refaddr($r1), refaddr($r2),
        'on_complete for ParenExpr always returns same reset (one) object');
    is(refaddr($r1), refaddr($prec->one()),
        'on_complete for ParenExpr returns the one() singleton');
}

# Test 45: on_complete for PostfixExpression returns same interned object
{
    my $r1 = $prec->on_complete($prec->one(), 'PostfixExpression', 0, 0, 0);
    my $r2 = $prec->on_complete($prec->one(), 'PostfixExpression', 0, 0, 0);
    is(refaddr($r1), refaddr($r2),
        'on_complete for PostfixExpression returns same interned object');
}

# Test 46: on_complete for Subscript (no high level) returns one singleton
{
    my $r = $prec->on_complete($prec->one(), 'Subscript', 0, 0, 0);
    is(refaddr($r), refaddr($prec->one()),
        'on_complete for Subscript with no high level returns one() singleton');
}

# Test 47: on_complete for generic rule returns one singleton
{
    my $r1 = $prec->on_complete($prec->one(), 'SomeOtherRule', 0, 0, 0);
    my $r2 = $prec->on_complete($prec->one(), 'AnotherRule', 0, 0, 0);
    is(refaddr($r1), refaddr($r2),
        'on_complete for unrecognised rules returns same one() singleton');
    is(refaddr($r1), refaddr($prec->one()),
        'on_complete for unrecognised rules returns the one() singleton');
}

# ========================================================================
# add() returns arrayref (migrated identity-detection protocol)
# ========================================================================

# Test 48: add(one, one) returns single-element arrayref containing one
{
    my $result = $prec->add($prec->one(), $prec->one());
    ok(ref($result) eq 'ARRAY', 'add() returns an arrayref');
    is(scalar @$result, 1, 'add() returns single-element arrayref');
    is(refaddr($result->[0]), refaddr($prec->one()),
        'add(one, one) returns [one()]');
}

# Test 49: add(zero, one) returns [one]
{
    my $result = $prec->add($prec->zero(), $prec->one());
    ok(ref($result) eq 'ARRAY', 'add(zero, one) returns arrayref');
    ok(!$prec->is_zero($result->[0]), 'add(zero, one) winner is not zero');
    is(refaddr($result->[0]), refaddr($prec->one()),
        'add(zero, one) returns [one()]');
}

# Test 50: add(one, zero) returns [one]
{
    my $result = $prec->add($prec->one(), $prec->zero());
    ok(ref($result) eq 'ARRAY', 'add(one, zero) returns arrayref');
    is(refaddr($result->[0]), refaddr($prec->one()),
        'add(one, zero) returns [one()]');
}

# Test 51: add(zero, zero) returns [zero]
{
    my $result = $prec->add($prec->zero(), $prec->zero());
    ok(ref($result) eq 'ARRAY', 'add(zero, zero) returns arrayref');
    ok($prec->is_zero($result->[0]), 'add(zero, zero) yields zero');
    is(refaddr($result->[0]), refaddr($prec->zero()),
        'add(zero, zero) returns [zero()]');
}

# Test 52: add(level, no-level) prefers level — returns arrayref with winner
{
    my $with_level = { valid => true, level => 5, op => '.', assoc => 'left' };
    my $no_level   = $prec->one();
    my $result = $prec->add($with_level, $no_level);
    ok(ref($result) eq 'ARRAY', 'add(level, no-level) returns arrayref');
    is(refaddr($result->[0]), refaddr($with_level),
        'add(level, no-level) returns the value with level');
}

# Test 53: add with identical interned objects returns [$left] (identity collapse)
{
    my $v = $prec->one();
    my $result = $prec->add($v, $v);
    ok(ref($result) eq 'ARRAY', 'add(same,same) returns arrayref');
    is(refaddr($result->[0]), refaddr($v),
        'add with identical objects returns [$left] (identity collapse)');
}

done_testing();
