# ABOUTME: Tests for packed-ambiguous Context handling in FilterComposite.
# ABOUTME: Validates distribution of multiply/add over packed Contexts (Phase 4).
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Context;

# ============================================================
# Synthetic semiring helpers (inline, no extra packages needed)
# ============================================================

package AbstainSR {
    use 5.42.0;
    use utf8;
    no warnings 'experimental::class';
    use experimental 'class';

    class AbstainSR {
        field $slot_name_val :param;
        method slot_name() { return $slot_name_val }
        method zero()      { Chalk::Bootstrap::Context->new(focus=>0,children=>[],position=>0,is_zero=>true) }
        method one()       { Chalk::Bootstrap::Context->new(focus=>1,children=>[],position=>0,is_zero=>false) }
        method is_zero($v) { blessed($v) && $v->can('is_zero') ? $v->is_zero() : !defined($v) }
        method multiply($l,$r) { return $r }
        method add($l,$r)  { return [$l,$r] }  # honest no-opinion
    }
}

package ZeroSR {
    use 5.42.0;
    use utf8;
    no warnings 'experimental::class';
    use experimental 'class';

    class ZeroSR {
        field $slot_name_val :param;
        method slot_name() { return $slot_name_val }
        method zero()      { Chalk::Bootstrap::Context->new(focus=>0,children=>[],position=>0,is_zero=>true) }
        method one()       { Chalk::Bootstrap::Context->new(focus=>1,children=>[],position=>0,is_zero=>false) }
        method is_zero($v) { blessed($v) && $v->can('is_zero') ? $v->is_zero() : !defined($v) }
        method multiply($l,$r) { return $r }
        method add($l,$r)  { return [] }  # eliminates both
    }
}

package LeftSR {
    use 5.42.0;
    use utf8;
    no warnings 'experimental::class';
    use experimental 'class';

    class LeftSR {
        field $slot_name_val :param;
        method slot_name() { return $slot_name_val }
        method zero()      { Chalk::Bootstrap::Context->new(focus=>0,children=>[],position=>0,is_zero=>true) }
        method one()       { Chalk::Bootstrap::Context->new(focus=>1,children=>[],position=>0,is_zero=>false) }
        method is_zero($v) { blessed($v) && $v->can('is_zero') ? $v->is_zero() : !defined($v) }
        method multiply($l,$r) { return $r }
        method add($l,$r)  { return [$l] }  # left wins
    }
}

package SASR {
    use 5.42.0;
    use utf8;
    no warnings 'experimental::class';
    use experimental 'class';

    class SASR {
        method zero()      { Chalk::Bootstrap::Context->new(focus=>0,children=>[],position=>0,is_zero=>true) }
        method one()       { Chalk::Bootstrap::Context->new(focus=>1,children=>[],position=>0,is_zero=>false) }
        method is_zero($v) { blessed($v) && $v->can('is_zero') ? $v->is_zero() : !defined($v) }
        method multiply($l,$r) { return $r }
        method add($l,$r)  { return [$l,$r] }
    }
}

# Helper: plain Context with focus + annotations
my sub ctx($focus, %ann) {
    return Chalk::Bootstrap::Context->new(
        focus       => $focus,
        children    => [],
        position    => 0,
        is_zero     => false,
        annotations => \%ann,
    );
}

# Helper: packed ambiguous Context
my sub packed(@alts) {
    return Chalk::Bootstrap::Context->new(
        focus        => undef,
        children     => \@alts,
        position     => 0,
        is_zero      => false,
        is_ambiguous => true,
        annotations  => {},
    );
}

# Helper: build a FilterComposite with AbstainSR + SA
my sub fc_abstain() {
    return Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [
            AbstainSR->new(slot_name_val => 'slot_a'),
            SASR->new(),
        ],
    );
}

my sub fc_zero() {
    return Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [
            ZeroSR->new(slot_name_val => 'slot_a'),
            SASR->new(),
        ],
    );
}

my sub fc_left() {
    return Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [
            LeftSR->new(slot_name_val => 'slot_a'),
            SASR->new(),
        ],
    );
}

# ============================================================
# Test: Context.is_ambiguous field
# ============================================================
subtest 'Context.is_ambiguous field defaults to false' => sub {
    my $c = ctx('X');
    ok($c->can('is_ambiguous'), 'Context has is_ambiguous reader');
    ok(!$c->is_ambiguous(), 'defaults to false');
};

subtest 'Context.is_ambiguous can be set to true' => sub {
    my $a = ctx('A');
    my $b = ctx('B');
    my $p = packed($a, $b);
    ok($p->is_ambiguous(), 'is_ambiguous is true on packed Context');
    is(scalar($p->children()->@*), 2, 'children holds both alternatives');
    is($p->children()->[0], $a, 'first child is A');
    is($p->children()->[1], $b, 'second child is B');
};

# ============================================================
# Test: add(non-packed, non-packed) when all abstain → packed
# ============================================================
subtest 'add(non-packed,non-packed) all-abstain → packed' => sub {
    my $fc = fc_abstain();
    my $left  = ctx('L', slot_a => 10);
    my $right = ctx('R', slot_a => 20);

    my $result = $fc->add($left, $right);

    ok(defined $result, 'add returns defined result');
    ok(!$result->is_zero(), 'result is not zero');
    ok($result->is_ambiguous(), 'result is packed (is_ambiguous)');
    is(scalar($result->children()->@*), 2, 'packed result has 2 children');
    is($result->children()->[0], $left,  'first child is left');
    is($result->children()->[1], $right, 'second child is right');
};

# ============================================================
# Test: add(non-packed, non-packed) with a verdict → still picks correctly
# ============================================================
subtest 'add(non-packed,non-packed) with left-wins verdict → left returned' => sub {
    my $fc = fc_left();
    my $left  = ctx('L', slot_a => 10);
    my $right = ctx('R', slot_a => 20);

    my $result = $fc->add($left, $right);

    ok(defined $result, 'add returns defined result');
    ok(!$result->is_ambiguous(), 'result is NOT packed when verdict was expressed');
    is($result, $left, 'left returned when LeftSR expresses left-wins');
};

# ============================================================
# Test: multiply(packed(A,B), C) distributes
# ============================================================
subtest 'multiply(packed(A,B), C) distributes over alternatives' => sub {
    my $fc = fc_abstain();

    # Build packed(A, B) by using add on two distinct contexts
    my $a = ctx('A', slot_a => 1);
    my $b = ctx('B', slot_a => 2);
    my $pk = packed($a, $b);
    ok($pk->is_ambiguous(), 'packed context is_ambiguous');

    # C is a plain context — multiply should distribute:
    # multiply(A, C) and multiply(B, C), collect non-zero survivors
    my $c = ctx('C', slot_a => 3);
    $c = Chalk::Bootstrap::Context->new(
        focus        => 'C',
        children     => [],
        position     => 0,
        is_zero      => false,
        annotations  => { complete => true, slot_a => 3 },
    );

    my $result = $fc->multiply($pk, $c);

    ok(defined $result, 'multiply(packed, C) returns defined result');
    ok(!$result->is_zero(), 'result is not zero');
    # Both A*C and B*C survive (abstain semiring never zeros), so we get a packed result
    ok($result->is_ambiguous(), 'result is packed (both A*C and B*C survived)');
    is(scalar($result->children()->@*), 2, 'two survivors in packed result');
};

# ============================================================
# Test: multiply(A, packed(C,D)) distributes (right operand)
# ============================================================
subtest 'multiply(A, packed(C,D)) distributes on right operand' => sub {
    my $fc = fc_abstain();

    my $a  = ctx('A', slot_a => 1);
    my $c  = Chalk::Bootstrap::Context->new(
        focus => 'C', children => [], position => 0, is_zero => false,
        annotations => { complete => true, slot_a => 3 },
    );
    my $d  = Chalk::Bootstrap::Context->new(
        focus => 'D', children => [], position => 0, is_zero => false,
        annotations => { complete => true, slot_a => 4 },
    );
    my $pk = packed($c, $d);
    ok($pk->is_ambiguous(), 'right operand is packed');

    my $result = $fc->multiply($a, $pk);

    ok(defined $result, 'multiply(A, packed) returns defined');
    ok(!$result->is_zero(), 'result is not zero');
    ok($result->is_ambiguous(), 'result is packed (both A*C and A*D survived)');
    is(scalar($result->children()->@*), 2, 'two survivors');
};

# ============================================================
# Test: multiply(packed(A,B), packed(C,D)) → 4 sub-multiplies
# ============================================================
subtest 'multiply(packed,packed) produces quadratic distribution' => sub {
    my $fc = fc_abstain();

    my $a = ctx('A', slot_a => 1);
    my $b = ctx('B', slot_a => 2);
    my $left_pk = packed($a, $b);

    my $c = Chalk::Bootstrap::Context->new(
        focus => 'C', children => [], position => 0, is_zero => false,
        annotations => { complete => true, slot_a => 3 },
    );
    my $d = Chalk::Bootstrap::Context->new(
        focus => 'D', children => [], position => 0, is_zero => false,
        annotations => { complete => true, slot_a => 4 },
    );
    my $right_pk = packed($c, $d);

    my $result = $fc->multiply($left_pk, $right_pk);

    ok(defined $result, 'multiply(packed,packed) returns defined');
    ok(!$result->is_zero(), 'result is not zero');
    ok($result->is_ambiguous(), 'result is packed');
    is(scalar($result->children()->@*), 4, '4 survivors from 2x2 distribution');
};

# ============================================================
# Test: when all sub-multiplies return zero, result is zero
# ============================================================
subtest 'multiply(packed,C): all zeros → result is zero' => sub {
    # To make multiply(a, c) return zero, either input must be zero or
    # a component semiring's multiply must return zero.
    # Simplest: use a zero C (is_zero=true) — both A*zero and B*zero are zero.
    my $fc = fc_abstain();

    my $a = ctx('A', slot_a => 1);
    my $b = ctx('B', slot_a => 2);
    my $pk = packed($a, $b);

    my $c_zero = Chalk::Bootstrap::Context->new(
        focus => undef, children => [], position => 0, is_zero => true, annotations => {},
    );

    my $result = $fc->multiply($pk, $c_zero);

    ok(defined $result, 'multiply returns defined even when all zero');
    ok($result->is_zero(), 'result is zero when all sub-multiplies were zero');
};

# ============================================================
# Test: exactly one sub-multiply returns non-zero → unpacked
# ============================================================
subtest 'multiply(packed,C): exactly one survivor → unpacked result' => sub {
    # ZeroSR for slot_a=1 would normally kill... but we need a more nuanced setup.
    # Use a custom FC where only A survives multiply with C (B does not).
    # Simplest: use multiply where one alt is itself is_zero.

    my $fc = fc_abstain();

    my $a   = ctx('A', slot_a => 1);
    my $b_z = Chalk::Bootstrap::Context->new(  # a zero Context in the packed set
        focus => undef, children => [], position => 0, is_zero => true, annotations => {},
    );
    my $pk = packed($a, $b_z);

    my $c = Chalk::Bootstrap::Context->new(
        focus => 'C', children => [], position => 0, is_zero => false,
        annotations => { complete => true, slot_a => 3 },
    );

    my $result = $fc->multiply($pk, $c);

    ok(defined $result, 'multiply returns defined');
    ok(!$result->is_zero(), 'result is not zero');
    ok(!$result->is_ambiguous(), 'result is NOT packed (exactly one survivor)');
};

# ============================================================
# Test: add(packed(A,B), C) merges C into survivor set
# ============================================================
subtest 'add(packed(A,B), C) merges C into survivor set' => sub {
    my $fc = fc_abstain();

    my $a = ctx('A', slot_a => 1);
    my $b = ctx('B', slot_a => 2);
    my $pk = packed($a, $b);

    my $c = ctx('C', slot_a => 3);

    my $result = $fc->add($pk, $c);

    ok(defined $result, 'add(packed, C) returns defined');
    ok(!$result->is_zero(), 'result not zero');
    ok($result->is_ambiguous(), 'result is still packed');
    # A abstains vs C, B abstains vs C — all three survive
    my @children = $result->children()->@*;
    ok(scalar(@children) >= 2, 'at least 2 children in merged packed');
};

done_testing();
