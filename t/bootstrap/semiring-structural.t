# ABOUTME: Tests for Structural semiring that disambiguates Block vs HashConstructor.
# ABOUTME: Covers basic ops, tagging, boundary resets, add() preference, and parser integration.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# ========================================================================
# Phase 1: Basic semiring operations (zero, one, is_zero, multiply, add)
# ========================================================================
use_ok('Chalk::Bootstrap::Semiring::Structural');

my $sr = Chalk::Bootstrap::Semiring::Structural->new();

# --- zero / one / is_zero ---
{
    my $z = $sr->zero();
    ok($sr->is_zero($z), 'zero is zero');

    my $o = $sr->one();
    ok(!$sr->is_zero($o), 'one is not zero');

    ok($o->{valid}, 'one has valid => true');
    ok(!$z->{valid}, 'zero has valid => false');
}

# --- multiply: zero propagation ---
{
    my $z = $sr->zero();
    my $o = $sr->one();

    ok($sr->is_zero($sr->multiply($z, $o)), 'zero * one = zero');
    ok($sr->is_zero($sr->multiply($o, $z)), 'one * zero = zero');
    ok($sr->is_zero($sr->multiply($z, $z)), 'zero * zero = zero');
    ok(!$sr->is_zero($sr->multiply($o, $o)), 'one * one is not zero');
}

# --- multiply: tag propagation ---
{
    my $block_val = { valid => true, is_block => true };
    my $hash_val  = { valid => true, is_hash  => true };
    my $plain     = $sr->one();

    my $r1 = $sr->multiply($block_val, $plain);
    ok($r1->{is_block}, 'block tag propagates from left through multiply');

    my $r2 = $sr->multiply($plain, $hash_val);
    ok($r2->{is_hash}, 'hash tag propagates from right through multiply');

    my $r3 = $sr->multiply($block_val, $hash_val);
    ok($r3->{is_block}, 'both tags: block propagates through multiply');
    ok($r3->{is_hash}, 'both tags: hash propagates through multiply');
}

# --- add: first non-zero when one is zero ---
{
    my $z = $sr->zero();
    my $o = $sr->one();

    my $r1 = $sr->add($z, $o);
    ok(!$sr->is_zero($r1), 'add(zero, one) = non-zero');

    my $r2 = $sr->add($o, $z);
    ok(!$sr->is_zero($r2), 'add(one, zero) = non-zero');

    ok($sr->is_zero($sr->add($z, $z)), 'add(zero, zero) = zero');
}

# --- add: prefer is_block over is_hash ---
{
    my $block_val = { valid => true, is_block => true };
    my $hash_val  = { valid => true, is_hash  => true };

    my $r1 = $sr->add($block_val, $hash_val);
    ok($r1->{is_block}, 'add(block, hash) prefers block');
    ok(!$r1->{is_hash}, 'add(block, hash) does not carry hash tag');

    my $r2 = $sr->add($hash_val, $block_val);
    ok($r2->{is_block}, 'add(hash, block) still prefers block');
    ok(!$r2->{is_hash}, 'add(hash, block) does not carry hash tag');
}

# --- add: both valid, neither tagged ---
{
    my $o1 = $sr->one();
    my $o2 = $sr->one();

    my $r = $sr->add($o1, $o2);
    ok(!$sr->is_zero($r), 'add(one, one) is not zero');
    ok($r->{valid}, 'add(one, one) is valid');
}

# ========================================================================
# Phase 2: on_scan (transparency)
# ========================================================================

# Mock item for on_scan/on_complete testing
my sub mock_item($rule_name, $value) {
    return {
        rule  => bless({ _name => $rule_name }, 'MockRule'),
        value => $value,
    };
}

# Provide a name() method for MockRule
{
    package MockRule;
    sub name { return $_[0]->{_name} }
}

{
    my $o = $sr->one();
    my $item = mock_item('Identifier', $o);
    my $r = $sr->on_scan($item, 0, 0, 'foo');
    ok(!$sr->is_zero($r), 'on_scan is transparent for Identifier');
    ok($r->{valid}, 'on_scan result is valid');
}

{
    my $z = $sr->zero();
    my $item = mock_item('Identifier', $z);
    my $r = $sr->on_scan($item, 0, 0, 'foo');
    ok($sr->is_zero($r), 'on_scan propagates zero');
}

{
    my $block_val = { valid => true, is_block => true };
    my $item = mock_item('Block', $block_val);
    my $r = $sr->on_scan($item, 0, 0, '{');
    ok($r->{is_block}, 'on_scan preserves block tag through multiply');
}

# ========================================================================
# Phase 3: on_complete (tagging and boundary clearing)
# ========================================================================

# --- Block completion → is_block tag ---
{
    my $o = $sr->one();
    my $item = mock_item('Block', $o);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'Block completion is valid');
    ok($r->{is_block}, 'Block completion sets is_block tag');
    ok(!$r->{is_hash}, 'Block completion does not set is_hash');
}

# --- HashConstructor completion → is_hash tag ---
{
    my $o = $sr->one();
    my $item = mock_item('HashConstructor', $o);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'HashConstructor completion is valid');
    ok($r->{is_hash}, 'HashConstructor completion sets is_hash tag');
    ok(!$r->{is_block}, 'HashConstructor completion does not set is_block');
}

# --- Boundary rules clear tags ---
for my $boundary_rule (qw(ParenExpr ArrayConstructor Program StatementList)) {
    my $tagged = { valid => true, is_block => true, is_hash => true };
    my $item = mock_item($boundary_rule, $tagged);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), "$boundary_rule completion is valid");
    ok(!$r->{is_block}, "$boundary_rule clears is_block tag");
    ok(!$r->{is_hash}, "$boundary_rule clears is_hash tag");
}

# --- Other rules pass through ---
{
    my $block_val = { valid => true, is_block => true };
    my $item = mock_item('Expression', $block_val);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'Expression completion is valid');
    ok($r->{is_block}, 'Expression passes through is_block tag');
}

{
    my $hash_val = { valid => true, is_hash => true };
    my $item = mock_item('Atom', $hash_val);
    my $r = $sr->on_complete($item, 0, 0);
    ok(!$sr->is_zero($r), 'Atom completion is valid');
    ok($r->{is_hash}, 'Atom passes through is_hash tag');
}

# --- Zero propagation ---
{
    my $z = $sr->zero();
    my $item = mock_item('Block', $z);
    my $r = $sr->on_complete($item, 0, 0);
    ok($sr->is_zero($r), 'on_complete propagates zero');
}

done_testing();
