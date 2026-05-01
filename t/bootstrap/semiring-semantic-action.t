# ABOUTME: Tests SemanticAction semiring for building IR from parse results
# ABOUTME: Verifies zero, one, multiply, add operations with Context values
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::IR::NodeFactory;

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

# Helper: build a complete-annotated Context for multiply() calls.
# Replaces on_complete($value, $rule_name, $alt_idx, $pos, $origin).
sub make_complete_ctx($value, $rule_name, $alt_idx, $pos, $origin) {
    $pos    //= 0;
    $origin //= 0;
    $alt_idx //= 0;
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
}
# Reset factory for clean test environment
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Test 1: zero creates a Context with is_zero=true (per Decision 4 contract migration)
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $zero = $sr->zero();

    ok($sr->is_zero($zero), 'zero creates zero context');
    isa_ok($zero, 'Chalk::Bootstrap::Context', 'zero returns Context');
    ok($zero->is_zero(), 'zero Context has is_zero=true');
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

# Test 7: multiply with scan Context returns Context with matched text accessible via scanned_text()
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $scan_val = $sr->multiply($sr->one(), make_scan_ctx('SomeRule', 'hello'));

    isa_ok($scan_val, 'Chalk::Bootstrap::Context', 'multiply with scan Context returns Context');
    # multiply with scan context creates a parent Context; scan text is in a child
    ok(defined $scan_val, 'multiply with scan Context produces defined result');
}

# Test 8: multiply with scan Context and empty string
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $scan_val = $sr->multiply($sr->one(), make_scan_ctx('SomeRule', ''));

    isa_ok($scan_val, 'Chalk::Bootstrap::Context', 'multiply with empty scan Context returns Context');
    ok(defined $scan_val, 'multiply with empty scan Context produces defined result');
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

    my $result = $sr->multiply($ctx, make_complete_ctx($ctx, 'TestRule', 0, 5, 0));

    isa_ok($result, 'Chalk::Bootstrap::Context', 'multiply with complete Context returns Context');
    is($result->extract(), 'HELLO', 'multiply with complete Context applies action to compute new focus');
    is($result->rule(), 'TestRule', 'multiply with complete Context sets rule name on result');
}

# Test 10: multiply with complete Context for unknown rule returns value with rule set
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'hello',
        children => [],
        position => 0,
        rule     => undef,
    );

    my $result = $sr->multiply($ctx, make_complete_ctx($ctx, 'UnknownRule', 0, 5, 0));

    isa_ok($result, 'Chalk::Bootstrap::Context', 'multiply with complete Context returns Context for unknown rule');
    is($result->rule(), 'UnknownRule', 'multiply with complete Context sets rule even without action');
    is($result->extract(), 'hello', 'multiply with complete Context preserves focus for unknown rule');
}

# Test 11: multiply with zero left propagates zero (per Decision 4 contract migration)
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    # zero() is a Context with is_zero=true; multiply propagates zero
    # immediately without touching $right.
    my $result = $sr->multiply($sr->zero(), make_complete_ctx($sr->one(), 'TestRule', 0, 5, 0));

    ok($sr->is_zero($result), 'multiply with zero left propagates zero');
    isa_ok($result, 'Chalk::Bootstrap::Context', 'multiply with zero left returns Context');
}

# Test 12: one() is a singleton — same refaddr on repeated calls
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $one_a = $sr->one();
    my $one_b = $sr->one();

    ok(defined $one_a, 'one() returns defined value');
    is(refaddr($one_a), refaddr($one_b), 'one() is a singleton (same refaddr each call)');
}

# Test 13: multiply with the same scan Context (same object) produces same hash-consed result
# SA.multiply is keyed by the refaddrs of its left and right arguments.
# When left and right are the same objects, the result is always the same object.
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $scan_ctx = make_scan_ctx('SomeRule', 'foo');
    my $scan_a = $sr->multiply($sr->one(), $scan_ctx);
    my $scan_b = $sr->multiply($sr->one(), $scan_ctx);

    is(refaddr($scan_a), refaddr($scan_b),
        'multiply with same scan Context produces same refaddr (hash-consed)');
}

# Test 14: multiply with different scan Contexts (different text) produces different refaddr
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $scan_foo = make_scan_ctx('SomeRule', 'foo');
    my $scan_bar = make_scan_ctx('SomeRule', 'bar');
    my $scan_a = $sr->multiply($sr->one(), $scan_foo);
    my $scan_b = $sr->multiply($sr->one(), $scan_bar);

    isnt(refaddr($scan_a), refaddr($scan_b),
        'multiply with different scan Contexts produces different refaddr');
}

# Test 15: multiply produces hash-consed result
# Same children pair (same refaddrs) → same refaddr for result
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx_a = $sr->multiply($sr->one(), make_scan_ctx('SomeRule', 'left'));
    my $ctx_b = $sr->multiply($sr->one(), make_scan_ctx('SomeRule', 'right'));

    my $mul1 = $sr->multiply($ctx_a, $ctx_b);
    my $mul2 = $sr->multiply($ctx_a, $ctx_b);

    is(refaddr($mul1), refaddr($mul2),
        'multiply with same children produces same refaddr (hash-consed)');
}

# Test 16: multiply with different children produces different refaddr
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();

    my $ctx_a = $sr->multiply($sr->one(), make_scan_ctx('SomeRule', 'left'));
    my $ctx_b = $sr->multiply($sr->one(), make_scan_ctx('SomeRule', 'right'));
    my $ctx_c = $sr->multiply($sr->one(), make_scan_ctx('SomeRule', 'other'));

    my $mul1 = $sr->multiply($ctx_a, $ctx_b);
    my $mul2 = $sr->multiply($ctx_a, $ctx_c);

    isnt(refaddr($mul1), refaddr($mul2),
        'multiply with different children produces different refaddr');
}

# Test 17: multiply with complete Context produces a new Context each call (not hash-consed)
# SA._complete_sa is not hash-consed because semantic actions depend on the
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

    my $result_a = $sr->multiply($ctx, make_complete_ctx($ctx, 'SomeRule', 0, 5, 0));
    my $result_b = $sr->multiply($ctx, make_complete_ctx($ctx, 'SomeRule', 0, 5, 0));

    isa_ok($result_a, 'Chalk::Bootstrap::Context',
        'multiply with complete Context returns Context');
    is($result_a->rule(), 'SomeRule',
        'multiply with complete Context sets rule name');
    is($result_a->extract(), 'hello',
        'multiply with complete Context preserves focus (no action registered)');
    # Two separate calls produce structurally equivalent but distinct objects
    # (not hash-consed — unsafe to cache due to actions-object dependency)
    is($result_b->rule(), 'SomeRule',
        'second multiply with complete Context also sets rule name');
    is($result_b->extract(), 'hello',
        'second multiply with complete Context also preserves focus');
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
