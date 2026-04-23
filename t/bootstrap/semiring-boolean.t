# ABOUTME: Tests for Chalk::Bootstrap::Semiring::Boolean recognition semiring.
# ABOUTME: Validates zero, one, multiply, add operations and zero detection.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Semiring::Boolean;

# Create a semiring instance
my $sr = Chalk::Bootstrap::Semiring::Boolean->new();

# Test 1: Zero value
{
    my $zero = $sr->zero();
    ok(defined $zero, "zero returns a defined value");
    ok($sr->is_zero($zero), "zero value is detected as zero");
}

# Test 2: One value
{
    my $one = $sr->one();
    ok(defined $one, "one returns a defined value");
    ok(!$sr->is_zero($one), "one value is not detected as zero");
}

# Test 3: Zero and one are distinct
{
    my $zero = $sr->zero();
    my $one = $sr->one();
    isnt($zero, $one, "zero and one are different values");
}

# Test 4: Multiply operation (sequence)
{
    my $one = $sr->one();
    my $result = $sr->multiply($one, $one);
    ok(!$sr->is_zero($result), "one * one = one (not zero)");

    my $zero = $sr->zero();
    my $result2 = $sr->multiply($one, $zero);
    ok($sr->is_zero($result2), "one * zero = zero");

    my $result3 = $sr->multiply($zero, $one);
    ok($sr->is_zero($result3), "zero * one = zero");

    my $result4 = $sr->multiply($zero, $zero);
    ok($sr->is_zero($result4), "zero * zero = zero");
}

# Test 5: Add operation (alternative)
{
    my $one = $sr->one();
    my $result = $sr->add($one, $one);
    ok(!$sr->is_zero($result), "one + one = one (not zero)");

    my $zero = $sr->zero();
    my $result2 = $sr->add($one, $zero);
    ok(!$sr->is_zero($result2), "one + zero = one");

    my $result3 = $sr->add($zero, $one);
    ok(!$sr->is_zero($result3), "zero + one = one");

    my $result4 = $sr->add($zero, $zero);
    ok($sr->is_zero($result4), "zero + zero = zero");
}

# Test 6: Semiring identities
{
    my $zero = $sr->zero();
    my $one = $sr->one();

    # Multiplicative identity: one * x = x
    my $x = $sr->one();
    my $result = $sr->multiply($one, $x);
    ok(!$sr->is_zero($result), "multiplicative identity: one * one = one");

    # Multiplicative annihilator: zero * x = zero
    my $result2 = $sr->multiply($zero, $x);
    ok($sr->is_zero($result2), "multiplicative annihilator: zero * one = zero");

    # Additive identity: zero + x = x
    my $result3 = $sr->add($zero, $x);
    ok(!$sr->is_zero($result3), "additive identity: zero + one = one");
}

# Test 7: Multiple add operations (alternatives)
{
    my $zero = $sr->zero();
    my $one = $sr->one();

    # Simulate parsing with multiple alternatives
    my $result = $zero;
    $result = $sr->add($result, $zero);  # First alternative failed
    ok($sr->is_zero($result), "accumulated result still zero after adding zero");

    $result = $sr->add($result, $one);   # Second alternative succeeded
    ok(!$sr->is_zero($result), "accumulated result becomes one after adding one");

    $result = $sr->add($result, $zero);  # Third alternative failed
    ok(!$sr->is_zero($result), "accumulated result stays one after adding zero");

    $result = $sr->add($result, $one);   # Fourth alternative succeeded
    ok(!$sr->is_zero($result), "accumulated result stays one after adding one");
}

# Test 8: Multiple multiply operations (sequences)
{
    my $one = $sr->one();

    # Simulate parsing a sequence: A B C
    my $result = $one;
    $result = $sr->multiply($result, $one);  # Matched A
    ok(!$sr->is_zero($result), "sequence continues after first match");

    $result = $sr->multiply($result, $one);  # Matched B
    ok(!$sr->is_zero($result), "sequence continues after second match");

    $result = $sr->multiply($result, $one);  # Matched C
    ok(!$sr->is_zero($result), "complete sequence matches");
}

# Test 9: Sequence with failure
{
    my $zero = $sr->zero();
    my $one = $sr->one();

    # Simulate parsing a sequence where one element fails: A B (fail)
    my $result = $one;
    $result = $sr->multiply($result, $one);  # Matched A
    ok(!$sr->is_zero($result), "sequence starts successfully");

    $result = $sr->multiply($result, $zero); # Failed to match B
    ok($sr->is_zero($result), "sequence fails when any element fails");
}

# Test 10: Is_zero with non-semiring values (should handle gracefully)
{
    ok(!$sr->is_zero(undef), "undef is not zero");
    ok(!$sr->is_zero(1), "arbitrary value 1 is not zero");
    ok(!$sr->is_zero(0), "arbitrary value 0 is not zero");
    ok(!$sr->is_zero("false"), "string 'false' is not zero");
}

# Test 10b: Unified-context invariant — all ops return Context objects.
# Boolean must obey `(Context, Context) -> Context` like every other semiring.
{
    use Chalk::Bootstrap::Context;
    isa_ok($sr->zero(), 'Chalk::Bootstrap::Context', 'zero() returns a Context');
    isa_ok($sr->one(),  'Chalk::Bootstrap::Context', 'one() returns a Context');

    my $one  = $sr->one();
    my $zero = $sr->zero();

    isa_ok($sr->multiply($one,  $one),  'Chalk::Bootstrap::Context',
        'multiply(one, one) returns a Context');
    isa_ok($sr->multiply($one,  $zero), 'Chalk::Bootstrap::Context',
        'multiply(one, zero) returns a Context');
    isa_ok($sr->multiply($zero, $one),  'Chalk::Bootstrap::Context',
        'multiply(zero, one) returns a Context');
    isa_ok($sr->add($one, $zero), 'Chalk::Bootstrap::Context',
        'add(one, zero) returns a Context');
    isa_ok($sr->add($zero, $zero), 'Chalk::Bootstrap::Context',
        'add(zero, zero) returns a Context');

    # multiply preserves parse shape — operands appear as children.
    my $product = $sr->multiply($one, $one);
    is(scalar($product->children->@*), 2,
        'multiply builds structural Context with both operands as children');
}

# Test 11: multiply with scan Context returns non-zero value (ignores terminal text)
# Scan events arrive as multiply($value, $scan_ctx) in the unified protocol.
{
    use Chalk::Bootstrap::Context;
    my $one = $sr->one();
    my $scan_ctx = Chalk::Bootstrap::Context->new(
        focus       => 'hello',
        position    => 0,
        annotations => { scan => true, rule_name => 'SomeRule', alt_idx => 0, predicted => {} },
    );
    my $scan_val = $sr->multiply($one, $scan_ctx);
    ok(!$sr->is_zero($scan_val), "multiply with scan Context returns non-zero value");

    # empty string scan also returns non-zero
    my $empty_ctx = Chalk::Bootstrap::Context->new(
        focus       => '',
        position    => 0,
        annotations => { scan => true, rule_name => 'SomeRule', alt_idx => 0, predicted => {} },
    );
    my $scan_empty = $sr->multiply($one, $empty_ctx);
    ok(!$sr->is_zero($scan_empty), "multiply with empty scan Context returns non-zero value");
}

# Test 12: Boolean semiring treats complete events as identity (pass-through)
# on_complete was removed; use multiply with a complete-annotated Context.
{
    use Chalk::Bootstrap::Context;
    my $make_complete = sub ($value, $rule_name, $alt_idx, $pos, $origin) {
        return Chalk::Bootstrap::Context->new(
            focus       => undef,
            children    => [$value],
            position    => $pos,
            annotations => {
                complete  => true,
                rule_name => $rule_name,
                alt_idx   => $alt_idx,
                pos       => $pos,
                origin    => $origin,
            },
        );
    };

    my $one = $sr->one();
    my $result = $sr->multiply($one, $make_complete->($one, 'SomeRule', 0, 5, 0));
    ok(!$sr->is_zero($result), "multiply with complete Context returns non-zero for non-zero input");

    my $zero = $sr->zero();
    my $result2 = $sr->multiply($zero, $make_complete->($zero, 'SomeRule', 0, 5, 0));
    ok($sr->is_zero($result2), "multiply with complete Context returns zero for zero input");
}

# Test 13: add preserves both derivations when both are non-zero.
# When two non-zero values are added, the result should contain both
# as children so downstream semirings can see the ambiguity, and the
# wrapper must carry annotations->{ambiguous} so a tree walker can
# distinguish ambiguity from structural multiply-composition.
{
    use Chalk::Bootstrap::Context;
    my $left = Chalk::Bootstrap::Context->new(
        focus    => true,
        children => [],
        is_zero  => false,
    );
    my $right = Chalk::Bootstrap::Context->new(
        focus    => true,
        children => [],
        is_zero  => false,
    );

    my $result = $sr->add($left, $right);
    ok(!$sr->is_zero($result), 'add(non-zero, non-zero) is non-zero');
    isa_ok($result, 'Chalk::Bootstrap::Context', 'add returns a Context');

    my @kids = $result->children()->@*;
    is(scalar @kids, 2,
        'add(non-zero, non-zero) preserves both derivations as children');
    is($kids[0], $left,  'first child is left derivation');
    is($kids[1], $right, 'second child is right derivation');

    ok($result->annotations->{ambiguous},
        'add wrapper is tagged annotations->{ambiguous}');
}

# Test 14: add with one zero still returns just the survivor, not a wrapper.
{
    use Chalk::Bootstrap::Context;
    my $one = $sr->one();
    my $zero = $sr->zero();

    my $result_lz = $sr->add($zero, $one);
    ok(!$sr->is_zero($result_lz), 'add(zero, one) is non-zero');
    is($result_lz, $one, 'add(zero, one) returns the survivor directly');

    my $result_rz = $sr->add($one, $zero);
    ok(!$sr->is_zero($result_rz), 'add(one, zero) is non-zero');
    is($result_rz, $one, 'add(one, zero) returns the survivor directly');
}

# Test 15: add with three alternatives accumulates all of them.
{
    use Chalk::Bootstrap::Context;
    my $a = Chalk::Bootstrap::Context->new(focus => true, is_zero => false);
    my $b = Chalk::Bootstrap::Context->new(focus => true, is_zero => false);
    my $c = Chalk::Bootstrap::Context->new(focus => true, is_zero => false);

    my $ab = $sr->add($a, $b);
    my $abc = $sr->add($ab, $c);

    ok(!$sr->is_zero($abc), 'three-way add is non-zero');
    my @kids = $abc->children()->@*;
    is(scalar @kids, 2, 'add($ab, $c) has two children');
    is($kids[0], $ab, 'first child is the $ab result');
    is($kids[1], $c,  'second child is $c');

    my @ab_kids = $ab->children()->@*;
    is(scalar @ab_kids, 2, '$ab has two children');
    is($ab_kids[0], $a, '$ab first child is $a');
    is($ab_kids[1], $b, '$ab second child is $b');
}

done_testing();
