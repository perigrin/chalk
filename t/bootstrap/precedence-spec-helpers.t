# ABOUTME: Regression tests for PrecedenceSpecHelpers — TODO propagation, shape_of, etc.
# ABOUTME: Guards against the local $TODO bug fixed by the $Test::Builder::Level bump.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';
use lib 't/bootstrap/lib';
use PrecedenceSpecHelpers qw(parse_expr shape_of isa_with_shape);

# parse_expr returns the initializer of `my $_ = EXPR;`.
subtest 'parse_expr returns the initializer expression' => sub {
    my $expr = parse_expr('1 + 2');
    isa_ok($expr, 'Chalk::IR::Node::Add', 'parse_expr returned Add node');
};

# shape_of produces a one-line description suitable for diagnostics.
subtest 'shape_of describes nested IR in a single line' => sub {
    my $expr = parse_expr('1 + 2 * 3');
    my $shape = shape_of($expr);
    like($shape, qr/^Add\(.*Multiply\(.*\)\)$/,
        "shape_of nests correctly: $shape");
};

# isa_with_shape returns the node on success so callers can chain.
subtest 'isa_with_shape returns node on success' => sub {
    my $expr = parse_expr('1 + 2');
    my $node = isa_with_shape($expr, 'Chalk::IR::Node::Add', 'top is Add');
    ok(defined $node, 'returned a defined node');
    is(ref($node), 'Chalk::IR::Node::Add', 'returned the same node');
};

# isa_with_shape returns undef on type mismatch.
subtest 'isa_with_shape returns undef on type mismatch' => sub {
    # Use TODO so the intentional mismatch doesn't fail the test run.
    TODO: {
        local $TODO = 'intentional type mismatch for return-value test';
        my $expr = parse_expr('1 + 2');
        my $node = isa_with_shape($expr, 'Chalk::IR::Node::Multiply',
            'expected Multiply (intentional fail)');
        ok(!defined $node, 'returned undef on mismatch')
            or diag('expected isa_with_shape to return undef');
    }
};

# REGRESSION: `local $TODO` set in the test file's package must reach
# Test::Builder when isa_with_shape calls fail()/pass(). Before the
# $Test::Builder::Level bump in PrecedenceSpecHelpers, this test would
# real-fail (exit 1) instead of TODO-failing.
subtest 'local $TODO in caller propagates into isa_with_shape' => sub {
    my $expr = parse_expr('1 + 2');
    TODO: {
        local $TODO = 'TODO propagation regression test';
        # Deliberately wrong; should TODO-fail, not real-fail.
        isa_with_shape($expr, 'Chalk::IR::Node::Multiply',
            'expected Multiply (TODO-failing)');
    }
    # If we reach here without the runner exiting non-zero, the TODO
    # was honored. The plan-level subtest 'ok' status confirms it.
    pass('reached end of subtest after TODO-failing isa_with_shape');
};

done_testing;
