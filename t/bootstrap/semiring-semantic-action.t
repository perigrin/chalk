# ABOUTME: Tests SemanticAction semiring for building IR from parse results
# ABOUTME: Verifies zero, one, multiply, add operations with Context values
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Grammar::Rule;

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

# Test 4: add dies on ambiguous parse (two different non-zero alternatives)
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

    eval { $sr->add($ctx1, $ctx2) };
    like($@, qr/Ambiguous parse/, 'add dies on two different non-zero alternatives');
}

# Test 4b: add returns context when same object on both sides (disambiguated)
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
    isa_ok($result, 'Chalk::Bootstrap::Context', 'add returns Context for same-object merge');
    is($result->extract()->value(), 'winner', 'add returns the disambiguated context');
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

# Test 6: add with zero returns other context
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

    is($result1->extract()->value(), 'test', 'add(zero, ctx) returns ctx');
    is($result2->extract()->value(), 'test', 'add(ctx, zero) returns ctx');
}

# Helper to build a mock item for on_scan/on_complete
my sub make_sem_item($rule_name, $value) {
    my $rule = Chalk::Grammar::Rule->new(
        name        => $rule_name,
        expressions => [[]],
    );
    return { rule => $rule, dot => 0, origin => 0, value => $value };
}

# Test 7: on_scan returns Context with matched text as focus
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $item = make_sem_item('SomeRule', $sr->one());
    my $scan_val = $sr->on_scan($item, 0, 0, 'hello');

    isa_ok($scan_val, 'Chalk::Bootstrap::Context', 'on_scan returns Context');
    # on_scan multiplies one() with scan context, so focus is undef (parent node)
    # but the scan text is in a child
    ok(defined $scan_val, 'on_scan produces defined result');
}

# Test 8: on_scan with empty string
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $item = make_sem_item('SomeRule', $sr->one());
    my $scan_val = $sr->on_scan($item, 0, 0, '');

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

    my $item = make_sem_item('TestRule', $ctx);
    my $result = $sr->on_complete($item, 0, 5);

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

    my $item = make_sem_item('UnknownRule', $ctx);
    my $result = $sr->on_complete($item, 0, 5);

    isa_ok($result, 'Chalk::Bootstrap::Context', 'on_complete returns Context for unknown rule');
    is($result->rule(), 'UnknownRule', 'on_complete sets rule even without action');
    is($result->extract(), 'hello', 'on_complete preserves focus for unknown rule');
}

# Test 11: on_complete with undef value (zero) returns undef
{
    my $sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $item = make_sem_item('TestRule', undef);
    my $result = $sr->on_complete($item, 0, 5);

    ok(!defined $result, 'on_complete with undef value returns undef');
}

done_testing();
