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

    my $var = $factory->make('Constant',
        const_type => 'string',
        value      => '$x',
    );

    my $init = $factory->make('Constant',
        const_type => 'string',
        value      => '42',
    );

    my $decl = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var,
        initializer => $init,
    );

    # Check producers (inputs) of decl - side-effect-shaped:
    # inputs[0]=control (undef when constructed via Shim without it),
    # inputs[1]=variable, inputs[2]=initializer.
    is(scalar($decl->inputs->@*), 3, 'decl has 3 inputs (control, variable, initializer)');
    is($decl->inputs->[1], $var,  'second input is variable');
    is($decl->inputs->[2], $init, 'third input is initializer');

    # Check consumers of var
    is(scalar($var->consumers->@*), 1, 'var has 1 consumer');
    is($var->consumers->[0], $decl, 'var consumed by decl');

    # Check consumers of init
    is(scalar($init->consumers->@*), 1, 'init has 1 consumer');
    is($init->consumers->[0], $decl, 'init consumed by decl');
}

# Test 2: Multiple consumers - same inputs deduplicated
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $shared_var  = $factory->make('Constant', const_type => 'string', value => '$shared_var');
    my $shared_init = $factory->make('Constant', const_type => 'string', value => 'shared_init');

    my $decl1 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $shared_var,
        initializer => $shared_init,
    );

    my $decl2 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $shared_var,
        initializer => $shared_init,
    );

    # Because of hash consing, decl1 and decl2 are the same
    is($decl1, $decl2, 'VarDecl nodes are deduplicated');

    # So shared_var still has only 1 consumer
    is(scalar($shared_var->consumers->@*), 1, 'shared_var has 1 consumer (deduplicated)');
}

# Test 3: Multiple consumers (non-deduplicated due to different initializers)
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $shared_var = $factory->make('Constant',
        const_type => 'string',
        value      => '$multi_var',
    );

    my $init1 = $factory->make('Constant',
        const_type => 'string',
        value      => 'init_a',
    );

    my $init2 = $factory->make('Constant',
        const_type => 'string',
        value      => 'init_b',
    );

    my $decl1 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $shared_var,
        initializer => $init1,
    );

    my $decl2 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $shared_var,
        initializer => $init2,
    );

    # Different initializers means different decls
    isnt($decl1, $decl2, 'decls differ due to different initializers');

    # So shared_var has 2 consumers
    is(scalar($shared_var->consumers->@*), 2, 'shared_var has 2 consumers');

    my %consumer_addrs = map { refaddr($_) => 1 } $shared_var->consumers->@*;
    ok($consumer_addrs{refaddr($decl1)}, 'decl1 is a consumer');
    ok($consumer_addrs{refaddr($decl2)}, 'decl2 is a consumer');
}

# Test 4: Graph traversal (VarDecl -> ArrayRefExpr chain)
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # Build: var_const -> decl -> arr (decl used as element in ArrayRefExpr)
    # ArrayRefExpr takes 'elements' which is an array input
    my $var  = $factory->make('Constant', const_type => 'string', value => '$leaf_var');
    my $init = $factory->make('Constant', const_type => 'string', value => 'leaf_val');

    my $decl = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var,
        initializer => $init,
    );

    # ArrayRefExpr takes elements as its single input (an array of nodes)
    my $arr = $factory->make('Constructor',
        class    => 'ArrayRefExpr',
        elements => [$decl],
    );

    # Traverse backward from arr
    is(scalar($arr->inputs->@*), 1, 'arr has 1 input');
    my $arr_input = $arr->inputs->[0];
    is(ref($arr_input), 'ARRAY', 'arr input is array ref');
    is($arr_input->[0], $decl, 'arr input contains decl');

    # Traverse forward from var
    is(scalar($var->consumers->@*), 1, 'var has 1 consumer');
    is($var->consumers->[0], $decl, 'var consumer is decl');

    is(scalar($decl->consumers->@*), 1, 'decl has 1 consumer');
    ok($decl->consumers->[0], 'decl has a consumer (arr)');
}

# Test 5: Consumer removal
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    my $shared = $factory->make('Constant',
        const_type => 'string',
        value      => '$removal_test',
    );

    my $init1 = $factory->make('Constant',
        const_type => 'string',
        value      => 'init_r1',
    );

    my $init2 = $factory->make('Constant',
        const_type => 'string',
        value      => 'init_r2',
    );

    my $decl1 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $shared,
        initializer => $init1,
    );

    my $decl2 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $shared,
        initializer => $init2,
    );

    # Verify initial state
    is(scalar($shared->consumers->@*), 2, 'shared has 2 consumers initially');

    # Remove one consumer
    $shared->remove_consumer($decl1);

    is(scalar($shared->consumers->@*), 1, 'shared has 1 consumer after removal');
    is($shared->consumers->[0], $decl2, 'remaining consumer is decl2');

    # Remove second consumer
    $shared->remove_consumer($decl2);

    is(scalar($shared->consumers->@*), 0, 'shared has no consumers after removal');
}

# Test 6: No circular references at creation
{
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

    # Verify a node's consumers don't include itself initially
    my $const = $factory->make('Constant',
        const_type => 'string',
        value      => 'circular_test',
    );

    my $has_self_consumer = grep { refaddr($_) == refaddr($const) } $const->consumers->@*;
    ok(!$has_self_consumer, 'node does not have itself as consumer');
}

done_testing;
