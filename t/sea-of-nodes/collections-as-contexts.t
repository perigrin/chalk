# ABOUTME: Test for collections as contexts (Issue #130 Phase 3)
# ABOUTME: Validates arrays and hashes using context abstraction with index/key namespaces

use v5.42;
use lib 'lib';
use Test::More;
use Test::Deep;

use Chalk::IR::Node;
use Chalk::IR::Graph;
use Chalk::IR::Builder;
use Chalk::IR::Context;
use Chalk::IR::Interpreter;

# Test array-as-context with ArrayValue node
subtest 'Array as context with index namespace' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    # Build Start node
    my $start = $builder->build_start_node('main');

    # Create array with literal values: my @arr = (1, 2, 3)
    # Step 1: Build an empty array context
    my $empty_ctx = Chalk::IR::Context->empty_context();

    # Step 2: Extend context with index:0, index:1, index:2
    my $const_1 = $builder->build_constant_node(1);
    my $const_2 = $builder->build_constant_node(2);
    my $const_3 = $builder->build_constant_node(3);

    # Build array context manually - store node objects directly
    my $array_ctx = $empty_ctx;
    $array_ctx = Chalk::IR::Context->extend_context(
        $array_ctx,
        Chalk::IR::Context->make_index_label(0),
        $const_1  # Store node object
    );
    $array_ctx = Chalk::IR::Context->extend_context(
        $array_ctx,
        Chalk::IR::Context->make_index_label(1),
        $const_2  # Store node object
    );
    $array_ctx = Chalk::IR::Context->extend_context(
        $array_ctx,
        Chalk::IR::Context->make_index_label(2),
        $const_3  # Store node object
    );

    # Create ArrayValue node wrapping the context
    # Include all element nodes as inputs for proper scheduling
    my $array_node_id = $builder->next_node_id();
    my $array_value = Chalk::IR::Node::ArrayValue->new(
        id => $array_node_id,
        inputs => [$start->id, $const_1->id, $const_2->id, $const_3->id],
        array_context => $array_ctx,
    );
    $graph->add_node($array_value);

    # Create ArrayGet to fetch element at index 1
    my $index_1 = $builder->build_constant_node(1);
    my $array_get = $builder->build_array_get_node($array_value, $index_1);

    # Return the fetched value
    my $return = $builder->build_return_node($array_get);

    # Execute and verify
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 2, 'Array context lookup returns correct value at index 1');
};

# Test array mutation with immutable context extension
subtest 'Array mutation with context extension' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    my $start = $builder->build_start_node('main');

    # Create array: my @arr = (10, 20)
    my $empty_ctx = Chalk::IR::Context->empty_context();
    my $const_10 = $builder->build_constant_node(10);
    my $const_20 = $builder->build_constant_node(20);

    my $array_ctx = $empty_ctx;
    $array_ctx = Chalk::IR::Context->extend_context(
        $array_ctx,
        Chalk::IR::Context->make_index_label(0),
        $const_10  # Store node object
    );
    $array_ctx = Chalk::IR::Context->extend_context(
        $array_ctx,
        Chalk::IR::Context->make_index_label(1),
        $const_20  # Store node object
    );

    my $array_node_id = $builder->next_node_id();
    my $array_value = Chalk::IR::Node::ArrayValue->new(
        id => $array_node_id,
        inputs => [$start->id, $const_10->id, $const_20->id],
        array_context => $array_ctx,
    );
    $graph->add_node($array_value);

    # Mutate: $arr[0] = 99
    # This should create a NEW context with extended binding
    my $const_99 = $builder->build_constant_node(99);
    my $index_0 = $builder->build_constant_node(0);
    my $array_set = $builder->build_array_set_node($array_value, $index_0, $const_99);

    # Fetch the mutated value
    my $array_get = $builder->build_array_get_node($array_set, $index_0);

    # Return the fetched value
    my $return = $builder->build_return_node($array_get);

    # Execute and verify
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 99, 'Array mutation extends context with new value');
};

# Test hash-as-context with key namespace
subtest 'Hash as context with key namespace' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    my $start = $builder->build_start_node('main');

    # Create hash: my %hash = (a => 10, b => 20)
    my $empty_ctx = Chalk::IR::Context->empty_context();
    my $const_10 = $builder->build_constant_node(10);
    my $const_20 = $builder->build_constant_node(20);

    my $hash_ctx = $empty_ctx;
    $hash_ctx = Chalk::IR::Context->extend_context(
        $hash_ctx,
        Chalk::IR::Context->make_key_label('a'),
        $const_10  # Store node object
    );
    $hash_ctx = Chalk::IR::Context->extend_context(
        $hash_ctx,
        Chalk::IR::Context->make_key_label('b'),
        $const_20  # Store node object
    );

    my $hash_node_id = $builder->next_node_id();
    my $hash_value = Chalk::IR::Node::HashValue->new(
        id => $hash_node_id,
        inputs => [$start->id, $const_10->id, $const_20->id],
        hash_context => $hash_ctx,
    );
    $graph->add_node($hash_value);

    # Fetch value at key 'b'
    my $key_b = $builder->build_constant_node('b', 'Str');
    my $hash_get = $builder->build_hash_get_node($hash_value, $key_b);

    # Return the fetched value
    my $return = $builder->build_return_node($hash_get);

    # Execute and verify
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 20, 'Hash context lookup returns correct value at key b');
};

done_testing();
