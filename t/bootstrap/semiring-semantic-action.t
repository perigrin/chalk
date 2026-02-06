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

# Test 4: add combines alternative derivations (returns first for now)
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

    isa_ok($result, 'Chalk::Bootstrap::Context', 'add returns Context');
    is($result->extract()->value(), 'alt1', 'add returns first alternative');
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

done_testing();
