# ABOUTME: Tests for IR use-def chains - verifies producer-consumer relationships
# ABOUTME: Ensures bidirectional graph traversal works correctly
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory to ensure clean test state (prevents cross-test contamination)
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

# Test 1: Simple producer-consumer relationship
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $const = $factory->make('Constant',
        const_type => 'string',
        value => 'test1'
    );

    my $type = $factory->make('Constant',
        const_type => 'string',
        value => 'terminal'
    );

    my $symbol = $factory->make('MakeSymbol',
        type => $type,
        value => $const,
        quantifier => undef
    );

    # Check producers (inputs) of symbol
    is(scalar($symbol->inputs->@*), 3, 'symbol has 3 inputs');
    is($symbol->inputs->[0], $type, 'first input is type');
    is($symbol->inputs->[1], $const, 'second input is value');
    is($symbol->inputs->[2], undef, 'third input is undef quantifier');

    # Check consumers of const
    is(scalar($const->consumers->@*), 1, 'const has 1 consumer');
    is($const->consumers->[0], $symbol, 'const consumed by symbol');

    # Check consumers of type
    is(scalar($type->consumers->@*), 1, 'type has 1 consumer');
    is($type->consumers->[0], $symbol, 'type consumed by symbol');
}

# Test 2: Multiple consumers
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $shared = $factory->make('Constant',
        const_type => 'string',
        value => 'shared'
    );

    my $type = $factory->make('Constant',
        const_type => 'string',
        value => 'terminal'
    );

    my $symbol1 = $factory->make('MakeSymbol',
        type => $type,
        value => $shared,
        quantifier => undef
    );

    my $symbol2 = $factory->make('MakeSymbol',
        type => $type,
        value => $shared,
        quantifier => undef
    );

    # Because of hash consing, symbol1 and symbol2 are the same
    is($symbol1, $symbol2, 'symbols are deduplicated');

    # So shared still has only 1 consumer
    is(scalar($shared->consumers->@*), 1, 'shared has 1 consumer (deduplicated)');
}

# Test 3: Multiple consumers (non-deduplicated)
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $shared = $factory->make('Constant',
        const_type => 'string',
        value => 'shared2'
    );

    my $type = $factory->make('Constant',
        const_type => 'string',
        value => 'terminal'
    );

    my $quant1 = $factory->make('Constant',
        const_type => 'string',
        value => '*'
    );

    my $quant2 = $factory->make('Constant',
        const_type => 'string',
        value => '+'
    );

    my $symbol1 = $factory->make('MakeSymbol',
        type => $type,
        value => $shared,
        quantifier => $quant1
    );

    my $symbol2 = $factory->make('MakeSymbol',
        type => $type,
        value => $shared,
        quantifier => $quant2
    );

    # Different quantifiers means different symbols
    isnt($symbol1, $symbol2, 'symbols differ due to quantifier');

    # So shared has 2 consumers
    is(scalar($shared->consumers->@*), 2, 'shared has 2 consumers');

    my %consumer_addrs = map { refaddr($_) => 1 } $shared->consumers->@*;
    ok($consumer_addrs{refaddr($symbol1)}, 'symbol1 is a consumer');
    ok($consumer_addrs{refaddr($symbol2)}, 'symbol2 is a consumer');
}

# Test 4: Graph traversal
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # Build: const -> symbol -> expression
    my $const = $factory->make('Constant',
        const_type => 'string',
        value => 'leaf'
    );

    my $type = $factory->make('Constant',
        const_type => 'string',
        value => 'terminal'
    );

    my $symbol = $factory->make('MakeSymbol',
        type => $type,
        value => $const,
        quantifier => undef
    );

    my $expr = $factory->make('MakeExpression',
        elements => [$symbol]
    );

    # Traverse backward from expr
    is(scalar($expr->inputs->@*), 1, 'expr has 1 input');
    my $expr_input = $expr->inputs->[0];
    is(ref($expr_input), 'ARRAY', 'expr input is array ref');
    is($expr_input->[0], $symbol, 'expr input contains symbol');

    # Traverse forward from const
    is(scalar($const->consumers->@*), 1, 'const has 1 consumer');
    is($const->consumers->[0], $symbol, 'const consumer is symbol');

    is(scalar($symbol->consumers->@*), 1, 'symbol has 1 consumer');
    # Note: MakeExpression stores elements as arrayref, so it's the consumer
    ok($symbol->consumers->[0], 'symbol has a consumer');
}

# Test 5: Consumer removal
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $const = $factory->make('Constant',
        const_type => 'string',
        value => 'removal_test'
    );

    my $type = $factory->make('Constant',
        const_type => 'string',
        value => 'terminal'
    );

    my $quant1 = $factory->make('Constant',
        const_type => 'string',
        value => '*'
    );

    my $quant2 = $factory->make('Constant',
        const_type => 'string',
        value => '+'
    );

    my $symbol1 = $factory->make('MakeSymbol',
        type => $type,
        value => $const,
        quantifier => $quant1
    );

    my $symbol2 = $factory->make('MakeSymbol',
        type => $type,
        value => $const,
        quantifier => $quant2
    );

    # Verify initial state
    is(scalar($const->consumers->@*), 2, 'const has 2 consumers initially');

    # Remove one consumer
    $const->remove_consumer($symbol1);

    is(scalar($const->consumers->@*), 1, 'const has 1 consumer after removal');
    is($const->consumers->[0], $symbol2, 'remaining consumer is symbol2');

    # Remove second consumer
    $const->remove_consumer($symbol2);

    is(scalar($const->consumers->@*), 0, 'const has no consumers after removal');
}

# Test 6: No circular references at creation
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # We can't create a node that references itself because:
    # 1. Inputs must be provided at construction time
    # 2. The node doesn't exist yet to be its own input

    # This is a structural guarantee, not something we need to test runtime
    # But let's verify a node's consumers don't include itself initially

    my $const = $factory->make('Constant',
        const_type => 'string',
        value => 'circular_test'
    );

    my $has_self_consumer = grep { refaddr($_) == refaddr($const) } $const->consumers->@*;
    ok(!$has_self_consumer, 'node does not have itself as consumer');
}

done_testing;
