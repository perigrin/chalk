# ABOUTME: Test for references with label indirection (Issue #130 Phase 4)
# ABOUTME: Validates Perl reference operators using context+label indirection model

use v5.42;
use lib 'lib';
use Test::More;
use Test::Deep;

use Chalk::IR::Node;
use Chalk::IR::Graph;
use Chalk::IR::Builder;
use Chalk::IR::Context;
use Chalk::IR::Interpreter;

# Test 1: Scalar reference creation and dereferencing
subtest 'Scalar reference creation and dereferencing' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    # Build Start node
    my $start = $builder->build_start_node('main');

    # my $x = 10;
    my $const_10 = $builder->build_constant_node(10);
    my $context = $builder->context;
    $context = Chalk::IR::Context->extend_context(
        $context,
        'lexical:$x',
        $const_10  # Store node object, not ID
    );
    $builder->set_context($context);

    # my $ref = \$x;
    my $ref_node = $builder->build_scalar_ref_node('$x');
    $context = Chalk::IR::Context->extend_context(
        $context,
        'lexical:$ref',
        $ref_node  # Store node object, not ID
    );
    $builder->set_context($context);

    # my $y = $$ref;
    my $deref_node = $builder->build_scalar_deref_node('$ref');

    # Return $y
    my $return = $builder->build_return_node($deref_node);

    # Execute and verify
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 10, 'Scalar dereferencing returns correct value');
};

# Test 2: Scalar reference mutation
subtest 'Scalar reference mutation' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    my $start = $builder->build_start_node('main');

    # my $x = 10;
    my $const_10 = $builder->build_constant_node(10);
    my $context = $builder->context;
    $context = Chalk::IR::Context->extend_context(
        $context,
        'lexical:$x',
        $const_10  # Store node object, not ID
    );
    $builder->set_context($context);

    # my $ref = \$x;
    my $ref_node = $builder->build_scalar_ref_node('$x');
    $context = Chalk::IR::Context->extend_context(
        $context,
        'lexical:$ref',
        $ref_node  # Store node object, not ID
    );
    $builder->set_context($context);

    # $$ref = 20;
    my $const_20 = $builder->build_constant_node(20);
    my $assign_node = $builder->build_scalar_deref_assign_node('$ref', $const_20);

    # Read $x after mutation
    my $x_after = $builder->build_load_node('$x');

    # Return $x
    my $return = $builder->build_return_node($x_after);

    # Execute and verify
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 20, 'Scalar dereference assignment updates original variable');
};

# Test 3: Element reference - THE KEY TEST
subtest 'Element reference to array element' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    my $start = $builder->build_start_node('main');

    # my @arr = (1, 2, 3);
    my $empty_ctx = Chalk::IR::Context->empty_context();
    my $const_1 = $builder->build_constant_node(1);
    my $const_2 = $builder->build_constant_node(2);
    my $const_3 = $builder->build_constant_node(3);

    my $array_ctx = $empty_ctx;
    $array_ctx = Chalk::IR::Context->extend_context(
        $array_ctx,
        Chalk::IR::Context->make_index_label(0),
        $const_1->id
    );
    $array_ctx = Chalk::IR::Context->extend_context(
        $array_ctx,
        Chalk::IR::Context->make_index_label(1),
        $const_2->id
    );
    $array_ctx = Chalk::IR::Context->extend_context(
        $array_ctx,
        Chalk::IR::Context->make_index_label(2),
        $const_3->id
    );

    my $array_node_id = $builder->next_node_id();
    my $array_value = Chalk::IR::Node::ArrayValue->new(
        id => $array_node_id,
        inputs => [$start->id, $const_1->id, $const_2->id, $const_3->id],
        array_context => $array_ctx,
    );
    $graph->add_node($array_value);

    # Store array in lexical context
    my $context = $builder->context;
    $context = Chalk::IR::Context->extend_context(
        $context,
        'lexical:@arr',
        $array_value  # Store node object
    );
    $builder->set_context($context);

    # my $ref = \$arr[1];
    my $index_1 = $builder->build_constant_node(1);
    my $ref_node = $builder->build_element_ref_node('@arr', $index_1);
    $context = Chalk::IR::Context->extend_context(
        $context,
        'lexical:$ref',
        $ref_node  # Store node object
    );
    $builder->set_context($context);

    # Read $$ref (should be 2, the value at index 1)
    my $deref_node = $builder->build_scalar_deref_node('$ref');

    # Return $$ref
    my $return = $builder->build_return_node($deref_node);

    # Execute and verify
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 2, 'Element reference dereferencing returns array element value');
};

# Test 4: Reference aliasing
subtest 'Reference aliasing - two refs to same element' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $graph = $builder->graph;

    my $start = $builder->build_start_node('main');

    # my @arr = (1, 2, 3);
    my $empty_ctx = Chalk::IR::Context->empty_context();
    my $const_1 = $builder->build_constant_node(1);
    my $const_2 = $builder->build_constant_node(2);
    my $const_3 = $builder->build_constant_node(3);

    my $array_ctx = $empty_ctx;
    $array_ctx = Chalk::IR::Context->extend_context(
        $array_ctx,
        Chalk::IR::Context->make_index_label(0),
        $const_1->id
    );
    $array_ctx = Chalk::IR::Context->extend_context(
        $array_ctx,
        Chalk::IR::Context->make_index_label(1),
        $const_2->id
    );
    $array_ctx = Chalk::IR::Context->extend_context(
        $array_ctx,
        Chalk::IR::Context->make_index_label(2),
        $const_3->id
    );

    my $array_node_id = $builder->next_node_id();
    my $array_value = Chalk::IR::Node::ArrayValue->new(
        id => $array_node_id,
        inputs => [$start->id, $const_1->id, $const_2->id, $const_3->id],
        array_context => $array_ctx,
    );
    $graph->add_node($array_value);

    # Store array in lexical context
    my $context = $builder->context;
    $context = Chalk::IR::Context->extend_context(
        $context,
        'lexical:@arr',
        $array_value  # Store node object
    );
    $builder->set_context($context);

    # my $ref1 = \$arr[1];
    my $index_1 = $builder->build_constant_node(1);
    my $ref1_node = $builder->build_element_ref_node('@arr', $index_1);
    $context = Chalk::IR::Context->extend_context(
        $context,
        'lexical:$ref1',
        $ref1_node  # Store node object
    );
    $builder->set_context($context);

    # my $ref2 = \$arr[1];
    my $ref2_node = $builder->build_element_ref_node('@arr', $index_1);
    $context = Chalk::IR::Context->extend_context(
        $context,
        'lexical:$ref2',
        $ref2_node  # Store node object
    );
    $builder->set_context($context);

    # Read $$ref1 and $$ref2 - should both be 2
    my $deref1 = $builder->build_scalar_deref_node('$ref1');
    my $deref2 = $builder->build_scalar_deref_node('$ref2');

    # Verify both return the same value (2)
    my $return = $builder->build_return_node($deref2);

    # Execute and verify
    my $interpreter = Chalk::IR::Interpreter->new(graph => $graph);
    my $result = $interpreter->execute();

    is($result, 2, 'Reference aliasing - both refs point to same element');
};

done_testing();
