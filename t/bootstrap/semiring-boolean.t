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

# Test 13: add(non_zero_a, non_zero_b) returns a Context distinct from both inputs.
# Boolean's contract: when both sides are live parses, it has no opinion on which
# derivation to prefer. The result must NOT be refaddr-equal to either input so
# FilterComposite cannot mistake "no opinion" for "left wins."
{
    use Chalk::Bootstrap::Context;
    use Scalar::Util qw(refaddr);

    my $a = $sr->multiply($sr->one(), $sr->one());  # distinct non-zero Context
    my $b = $sr->multiply($sr->one(), $sr->one());  # another distinct non-zero Context

    my $result = $sr->add($a, $b);

    ok(!$sr->is_zero($result),
        'add(non_zero_a, non_zero_b): result is non-zero');
    ok(refaddr($result) != refaddr($a),
        'add(non_zero_a, non_zero_b): result is not refaddr-identical to left input');
    ok(refaddr($result) != refaddr($b),
        'add(non_zero_a, non_zero_b): result is not refaddr-identical to right input');
}

done_testing();
