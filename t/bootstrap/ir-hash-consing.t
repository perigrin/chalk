# ABOUTME: Tests for IR node hash consing - verifies deduplication works correctly
# ABOUTME: Ensures identical IR nodes share same reference through NodeFactory
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

# Test 1: Duplicate constants deduplicated
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $const1 = $factory->make('Constant',
        const_type => 'string',
        value => 'hello'
    );

    my $const2 = $factory->make('Constant',
        const_type => 'string',
        value => 'hello'
    );

    is($const1, $const2, 'identical constants return same reference');
    is(refaddr($const1), refaddr($const2), 'reference addresses match');
}

# Test 2: Different constants not deduplicated
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $const1 = $factory->make('Constant',
        const_type => 'string',
        value => 'hello'
    );

    my $const2 = $factory->make('Constant',
        const_type => 'string',
        value => 'world'
    );

    isnt($const1, $const2, 'different constants are different references');
    isnt(refaddr($const1), refaddr($const2), 'reference addresses differ');
}

# Test 3: Complex node deduplication
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # Create shared input nodes
    my $type = $factory->make('Constant',
        const_type => 'string',
        value => 'terminal'
    );

    my $value = $factory->make('Constant',
        const_type => 'string',
        value => 'foo'
    );

    # Create two MakeSymbol nodes with same inputs
    my $symbol1 = $factory->make('MakeSymbol',
        type => $type,
        value => $value,
        quantifier => undef
    );

    my $symbol2 = $factory->make('MakeSymbol',
        type => $type,
        value => $value,
        quantifier => undef
    );

    is($symbol1, $symbol2, 'complex nodes with same inputs deduplicated');
}

# Test 4: Hash key determinism - same data different order
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # Create inputs in one order
    my $type1 = $factory->make('Constant',
        const_type => 'string',
        value => 'reference'
    );
    my $val1 = $factory->make('Constant',
        const_type => 'string',
        value => 'bar'
    );

    my $symbol1 = $factory->make('MakeSymbol',
        type => $type1,
        value => $val1,
        quantifier => undef
    );

    # Create inputs in different code path but same logical data
    my $type2 = $factory->make('Constant',
        const_type => 'string',
        value => 'reference'
    );
    my $val2 = $factory->make('Constant',
        const_type => 'string',
        value => 'bar'
    );

    my $symbol2 = $factory->make('MakeSymbol',
        type => $type2,
        value => $val2,
        quantifier => undef
    );

    is($symbol1, $symbol2, 'hash key generation is deterministic');
}

# Test 5: Nested deduplication
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # Build a small graph twice
    my $const1 = $factory->make('Constant',
        const_type => 'string',
        value => 'test'
    );
    my $type1 = $factory->make('Constant',
        const_type => 'string',
        value => 'terminal'
    );
    my $symbol1 = $factory->make('MakeSymbol',
        type => $type1,
        value => $const1,
        quantifier => undef
    );

    # Build same graph again
    my $const2 = $factory->make('Constant',
        const_type => 'string',
        value => 'test'
    );
    my $type2 = $factory->make('Constant',
        const_type => 'string',
        value => 'terminal'
    );
    my $symbol2 = $factory->make('MakeSymbol',
        type => $type2,
        value => $const2,
        quantifier => undef
    );

    is($const1, $const2, 'leaf nodes deduplicated');
    is($type1, $type2, 'intermediate nodes deduplicated');
    is($symbol1, $symbol2, 'root nodes deduplicated');
}

# Test 6: Factory singleton
{
    my $factory1 = Chalk::Bootstrap::IR::NodeFactory->instance;
    my $factory2 = Chalk::Bootstrap::IR::NodeFactory->instance;

    is($factory1, $factory2, 'factory returns same singleton instance');
    is(refaddr($factory1), refaddr($factory2), 'singleton reference addresses match');
}

done_testing;
