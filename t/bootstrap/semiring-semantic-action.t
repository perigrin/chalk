# ABOUTME: Tests SemanticAction semiring for building IR from parse results
# ABOUTME: Verifies zero, one, multiply, add operations with Context values
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::IR::NodeFactory;
# Reset factory for clean test environment
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Test 1: zero creates error/undef context
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $zero = $sr->zero();

    ok($sr->is_zero($zero), 'zero creates zero context');
    ok(!defined $zero, 'zero is undef');
}

# Test 2: one creates empty context
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $one = $sr->one();

    ok(!$sr->is_zero($one), 'one is not zero');
    isa_ok($one, 'Chalk::Bootstrap::Context', 'one returns Context');
    ok(!defined $one->extract(), 'one has undef focus');
}

# Test 3: multiply combines two contexts in sequence
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'left');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $node1,
        children => [],
        position => 0,
        rule     => 'Left',
    );

    my $node2 = $factory->make('Constant', const_type => 'string', value => 'right');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $node2,
        children => [],
        position => 5,
        rule     => 'Right',
    );

    my $result = $sr->multiply($ctx1, $ctx2);

    isa_ok($result, 'Chalk::Bootstrap::Context', 'multiply returns Context');
    is(scalar($result->children()->@*), 2, 'multiply creates context with 2 children');
    is($result->children()->[0]->extract()->value(), 'left', 'first child preserved');
    is($result->children()->[1]->extract()->value(), 'right', 'second child preserved');
}

# Test 4: add returns both survivors for ambiguous parse (two different non-zero alternatives)
# FilterComposite uses _filter_compare to find a preference; when none is found it
# picks left as a deterministic tie-break, so both survivors won't reach SemanticAction.
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $node1 = $factory->make('Constant', const_type => 'string', value => 'alt1');
    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $node1,
        children => [],
        position => 0,
        rule     => 'Alt1',
    );

    my $node2 = $factory->make('Constant', const_type => 'string', value => 'alt2');
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $node2,
        children => [],
        position => 0,
        rule     => 'Alt2',
    );

    my $result = $sr->add($ctx1, $ctx2);
    ok(ref($result) eq 'ARRAY', 'add returns arrayref for two different non-zero alternatives');
    is(scalar($result->@*), 2, 'add returns both survivors for ambiguous parse');
    is(refaddr($result->[0]), refaddr($ctx1), 'first survivor is ctx1');
    is(refaddr($result->[1]), refaddr($ctx2), 'second survivor is ctx2');
}

# Test 4b: add returns [$ctx] for identity collapse (same object on both sides)
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $node = $factory->make('Constant', const_type => 'string', value => 'winner');
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => $node,
        children => [],
        position => 0,
        rule     => 'Winner',
    );

    my $result = $sr->add($ctx, $ctx);
    ok(ref($result) eq 'ARRAY', 'add returns arrayref for same-object identity collapse');
    is(scalar($result->@*), 1, 'add returns single-element arrayref for identity collapse');
    is(refaddr($result->[0]), refaddr($ctx), 'add returns the disambiguated context');
}

# Test 5: multiply with zero propagates zero
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $node = $factory->make('Constant', const_type => 'string', value => 'test');
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => $node,
        children => [],
        position => 0,
        rule     => 'Test',
    );

    my $zero = $sr->zero();
    my $result1 = $sr->multiply($zero, $ctx);
    my $result2 = $sr->multiply($ctx, $zero);

    ok($sr->is_zero($result1), 'multiply(zero, ctx) is zero');
    ok($sr->is_zero($result2), 'multiply(ctx, zero) is zero');
}

# Test 6: add with zero returns single-element arrayref containing the non-zero ctx
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $node = $factory->make('Constant', const_type => 'string', value => 'test');
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => $node,
        children => [],
        position => 0,
        rule     => 'Test',
    );

    my $zero = $sr->zero();
    my $result1 = $sr->add($zero, $ctx);
    my $result2 = $sr->add($ctx, $zero);

    ok(ref($result1) eq 'ARRAY', 'add(zero, ctx) returns arrayref');
    is(scalar($result1->@*), 1, 'add(zero, ctx) arrayref has 1 element');
    is(refaddr($result1->[0]), refaddr($ctx), 'add(zero, ctx) arrayref contains ctx');

    ok(ref($result2) eq 'ARRAY', 'add(ctx, zero) returns arrayref');
    is(scalar($result2->@*), 1, 'add(ctx, zero) arrayref has 1 element');
    is(refaddr($result2->[0]), refaddr($ctx), 'add(ctx, zero) arrayref contains ctx');
}

# Test 7: on_scan returns Context with matched text as focus
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $scan_val = $sr->on_scan($sr->one(), 'SomeRule', 0, 0, 'hello');

    isa_ok($scan_val, 'Chalk::Bootstrap::Context', 'on_scan returns Context');
    # on_scan multiplies one() with scan context, so focus is undef (parent node)
    # but the scan text is in a child
    ok(defined $scan_val, 'on_scan produces defined result');
}

# Test 8: on_scan with empty string
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $scan_val = $sr->on_scan($sr->one(), 'SomeRule', 0, 0, '');

    isa_ok($scan_val, 'Chalk::Bootstrap::Context', 'on_scan("") returns Context');
    ok(defined $scan_val, 'on_scan("") produces defined result');
}

# Test 9: on_complete applies action via extend using actions object
{
    # Create a test class with an action method
    package TestActions {
        use 5.42.0;
        use experimental 'class';

        class TestActions {
            method TestRule($ctx) { return uc($ctx->extract() // ''); }
        }
    }

    my $actions = TestActions->new();
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'hello',
        children => [],
        position => 0,
        rule     => undef,
    );

    my $result = $sr->on_complete($ctx, 'TestRule', 0, 5, 0);

    isa_ok($result, 'Chalk::Bootstrap::Context', 'on_complete returns Context');
    is($result->extract(), 'HELLO', 'on_complete applies action to compute new focus');
    is($result->rule(), 'TestRule', 'on_complete sets rule name on result');
}

# Test 10: on_complete with unknown rule returns value with rule set
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'hello',
        children => [],
        position => 0,
        rule     => undef,
    );

    my $result = $sr->on_complete($ctx, 'UnknownRule', 0, 5, 0);

    isa_ok($result, 'Chalk::Bootstrap::Context', 'on_complete returns Context for unknown rule');
    is($result->rule(), 'UnknownRule', 'on_complete sets rule even without action');
    is($result->extract(), 'hello', 'on_complete preserves focus for unknown rule');
}

# Test 11: on_complete with undef value (zero) returns undef
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $result = $sr->on_complete(undef, 'TestRule', 0, 5, 0);

    ok(!defined $result, 'on_complete with undef value returns undef');
}

# Test 12: one() is a singleton — same refaddr on repeated calls
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $one_a = $sr->one();
    my $one_b = $sr->one();

    ok(defined $one_a, 'one() returns defined value');
    is(refaddr($one_a), refaddr($one_b), 'one() is a singleton (same refaddr each call)');
}

# Test 13: on_scan produces hash-consed scan context
# Same matched_text + pos → same refaddr for the resulting Context
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $scan_a = $sr->on_scan($sr->one(), 'SomeRule', 0, 3, 'foo');
    my $scan_b = $sr->on_scan($sr->one(), 'SomeRule', 0, 3, 'foo');

    is(refaddr($scan_a), refaddr($scan_b),
        'on_scan with same text+pos produces same refaddr (hash-consed)');
}

# Test 14: on_scan with different text produces different refaddr
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $scan_a = $sr->on_scan($sr->one(), 'SomeRule', 0, 3, 'foo');
    my $scan_b = $sr->on_scan($sr->one(), 'SomeRule', 0, 3, 'bar');

    isnt(refaddr($scan_a), refaddr($scan_b),
        'on_scan with different text produces different refaddr');
}

# Test 15: multiply produces hash-consed result
# Same children pair (same refaddrs) → same refaddr for result
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx_a = $sr->on_scan($sr->one(), 'SomeRule', 0, 0, 'left');
    my $ctx_b = $sr->on_scan($sr->one(), 'SomeRule', 0, 5, 'right');

    my $mul1 = $sr->multiply($ctx_a, $ctx_b);
    my $mul2 = $sr->multiply($ctx_a, $ctx_b);

    is(refaddr($mul1), refaddr($mul2),
        'multiply with same children produces same refaddr (hash-consed)');
}

# Test 16: multiply with different children produces different refaddr
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx_a = $sr->on_scan($sr->one(), 'SomeRule', 0, 0, 'left');
    my $ctx_b = $sr->on_scan($sr->one(), 'SomeRule', 0, 5, 'right');
    my $ctx_c = $sr->on_scan($sr->one(), 'SomeRule', 0, 10, 'other');

    my $mul1 = $sr->multiply($ctx_a, $ctx_b);
    my $mul2 = $sr->multiply($ctx_a, $ctx_c);

    isnt(refaddr($mul1), refaddr($mul2),
        'multiply with different children produces different refaddr');
}

# Test 17: on_complete produces a new Context each call (not hash-consed)
# on_complete is not hash-consed because semantic actions depend on the
# actions object and the result focus is not stable across different parses.
# Each call produces a new Context with the rule name and focus set correctly.
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'hello',
        children => [],
        position => 0,
        rule     => undef,
    );

    my $result_a = $sr->on_complete($ctx, 'SomeRule', 0, 5, 0);
    my $result_b = $sr->on_complete($ctx, 'SomeRule', 0, 5, 0);

    isa_ok($result_a, 'Chalk::Bootstrap::Context',
        'on_complete returns Context');
    is($result_a->rule(), 'SomeRule',
        'on_complete sets rule name');
    is($result_a->extract(), 'hello',
        'on_complete preserves focus (no action registered)');
    # Two separate calls produce structurally equivalent but distinct objects
    # (not hash-consed — unsafe to cache due to actions-object dependency)
    is($result_b->rule(), 'SomeRule',
        'second on_complete call also sets rule name');
    is($result_b->extract(), 'hello',
        'second on_complete call also preserves focus');
}

# Test 18: add() returns arrayref for zero/non-zero cases
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'test',
        children => [],
        position => 0,
        rule     => 'Test',
    );

    my $zero = $sr->zero();

    my $r1 = $sr->add($zero, $ctx);
    my $r2 = $sr->add($ctx, $zero);

    ok(ref($r1) eq 'ARRAY', 'add(zero, ctx) returns arrayref');
    is(scalar($r1->@*), 1, 'add(zero, ctx) arrayref has 1 element');
    is(refaddr($r1->[0]), refaddr($ctx), 'add(zero, ctx) arrayref contains ctx');

    ok(ref($r2) eq 'ARRAY', 'add(ctx, zero) returns arrayref');
    is(scalar($r2->@*), 1, 'add(ctx, zero) arrayref has 1 element');
    is(refaddr($r2->[0]), refaddr($ctx), 'add(ctx, zero) arrayref contains ctx');
}

# Test 19: add() returns [$left] for identity collapse (same refaddr)
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'winner',
        children => [],
        position => 0,
        rule     => 'Winner',
    );

    my $result = $sr->add($ctx, $ctx);

    ok(ref($result) eq 'ARRAY', 'add(ctx, ctx) returns arrayref');
    is(scalar($result->@*), 1, 'add(ctx, ctx) arrayref has 1 element');
    is(refaddr($result->[0]), refaddr($ctx), 'add(ctx, ctx) arrayref contains ctx');
}

# Test 20: add() returns [$left, $right] for two different non-zero values
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx_a = Chalk::Bootstrap::Context->new(
        focus    => 'alt_a',
        children => [],
        position => 0,
        rule     => 'AltA',
    );

    my $ctx_b = Chalk::Bootstrap::Context->new(
        focus    => 'alt_b',
        children => [],
        position => 0,
        rule     => 'AltB',
    );

    my $result = $sr->add($ctx_a, $ctx_b);

    ok(ref($result) eq 'ARRAY', 'add(ctx_a, ctx_b) returns arrayref');
    is(scalar($result->@*), 2, 'add(ctx_a, ctx_b) arrayref has 2 elements');
    is(refaddr($result->[0]), refaddr($ctx_a), 'first element is ctx_a');
    is(refaddr($result->[1]), refaddr($ctx_b), 'second element is ctx_b');
}

done_testing();
