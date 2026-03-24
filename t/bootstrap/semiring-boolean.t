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

# Test 11: on_scan returns non-zero value (ignores terminal text)
{
    my $one = $sr->one();
    my $scan_val = $sr->on_scan($one, 'SomeRule', 0, 0, 'hello');
    ok(!$sr->is_zero($scan_val), "on_scan returns non-zero value");

    # on_scan with empty string also returns non-zero
    my $scan_empty = $sr->on_scan($one, 'SomeRule', 0, 0, '');
    ok(!$sr->is_zero($scan_empty), "on_scan('') returns non-zero value");
}

# Test 12: on_complete returns value unchanged
{
    my $one = $sr->one();
    my $result = $sr->on_complete($one, 'SomeRule', 0, 5, 0);
    ok(!$sr->is_zero($result), "on_complete returns non-zero for non-zero input");

    my $zero = $sr->zero();
    my $result2 = $sr->on_complete($zero, 'SomeRule', 0, 5, 0);
    ok($sr->is_zero($result2), "on_complete returns zero for zero input");
}

done_testing();
