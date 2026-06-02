# ABOUTME: Tests for IR use-def chains - verifies producer-consumer relationships
# ABOUTME: Ensures bidirectional graph traversal works correctly
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::VarDecl;

# Reset factory to ensure clean test state (prevents cross-test contamination)

# Test 1: Simple producer-consumer relationship
{
    my $factory = Chalk::IR::NodeFactory->new;

    my $var = $factory->make('Constant',
        const_type => 'string',
        value      => '$x',
    );

    my $init = $factory->make('Constant',
        const_type => 'string',
        value      => '42',
    );

    my $typed = Chalk::IR::NodeFactory->new;
    my $decl  = $typed->make('VarDecl',
        inputs       => [$var, $init],
        compat_class => 'VarDecl',
    );

    # Check producers (inputs) of decl - side-effect-shaped:
    # inputs[0]=variable, inputs[1]=initializer. Control flows via the
    # control_in decoration, not an inputs slot.
    is(scalar($decl->inputs->@*), 2, 'decl has 2 inputs (variable, initializer)');
    is($decl->inputs->[0], $var,  'first input is variable');
    is($decl->inputs->[1], $init, 'second input is initializer');

    # Check consumers of var
    is(scalar($var->consumers->@*), 1, 'var has 1 consumer');
    is($var->consumers->[0], $decl, 'var consumed by decl');

    # Check consumers of init
    is(scalar($init->consumers->@*), 1, 'init has 1 consumer');
    is($init->consumers->[0], $decl, 'init consumed by decl');
}

# Test 2: Multiple consumers - identical VarDecls stay distinct
# VarDecl carries per-position (counter) identity, so two textually-identical
# declarations are distinct nodes (see Chalk::IR::Node::VarDecl). Each registers
# itself as a consumer of the shared inputs, so the shared input has 2 consumers.
{
    my $factory = Chalk::IR::NodeFactory->new;

    my $shared_var  = $factory->make('Constant', const_type => 'string', value => '$shared_var');
    my $shared_init = $factory->make('Constant', const_type => 'string', value => 'shared_init');

    my $typed = Chalk::IR::NodeFactory->new;
    my $decl1 = $typed->make('VarDecl',
        inputs       => [$shared_var, $shared_init],
        compat_class => 'VarDecl',
    );

    my $decl2 = $typed->make('VarDecl',
        inputs       => [$shared_var, $shared_init],
        compat_class => 'VarDecl',
    );

    # VarDecl has per-position identity: decl1 and decl2 are distinct
    isnt($decl1, $decl2, 'identical VarDecl nodes are distinct (per-position identity)');

    # Both distinct decls consume shared_var
    is(scalar($shared_var->consumers->@*), 2, 'shared_var has 2 consumers (one per distinct decl)');
}

# Test 3: Multiple consumers (non-deduplicated due to different initializers)
{
    my $factory = Chalk::IR::NodeFactory->new;

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

    my $typed = Chalk::IR::NodeFactory->new;
    my $decl1 = $typed->make('VarDecl',
        inputs       => [$shared_var, $init1],
        compat_class => 'VarDecl',
    );

    my $decl2 = $typed->make('VarDecl',
        inputs       => [$shared_var, $init2],
        compat_class => 'VarDecl',
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
    my $factory = Chalk::IR::NodeFactory->new;

    # Build: var_const -> decl -> arr (decl used as element in ArrayRefExpr)
    # ArrayRefExpr takes 'elements' which is an array input
    my $var  = $factory->make('Constant', const_type => 'string', value => '$leaf_var');
    my $init = $factory->make('Constant', const_type => 'string', value => 'leaf_val');

    my $typed = Chalk::IR::NodeFactory->new;
    my $decl  = $typed->make('VarDecl',
        inputs       => [$var, $init],
        compat_class => 'VarDecl',
    );

    # ArrayRefExpr takes elements as its single input (an array of nodes)
    my $arr = $typed->make('ArrayRef',
        inputs       => [[$decl]],
        compat_class => 'ArrayRefExpr',
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
    my $factory = Chalk::IR::NodeFactory->new;

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

    my $typed = Chalk::IR::NodeFactory->new;
    my $decl1 = $typed->make('VarDecl',
        inputs       => [$shared, $init1],
        compat_class => 'VarDecl',
    );

    my $decl2 = $typed->make('VarDecl',
        inputs       => [$shared, $init2],
        compat_class => 'VarDecl',
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
    my $factory = Chalk::IR::NodeFactory->new;

    # Verify a node's consumers don't include itself initially
    my $const = $factory->make('Constant',
        const_type => 'string',
        value      => 'circular_test',
    );

    my $has_self_consumer = grep { refaddr($_) == refaddr($const) } $const->consumers->@*;
    ok(!$has_self_consumer, 'node does not have itself as consumer');
}

done_testing;
