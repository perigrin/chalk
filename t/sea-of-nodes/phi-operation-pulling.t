#!/usr/bin/env perl
# ABOUTME: Test Phi operation pulling optimization (Issue #253)
# ABOUTME: Validates that Phi(region, Op(a,b), Op(c,d)) -> Op(Phi(region,a,c), Phi(region,b,d))

use lib 'lib';
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node;
use Chalk::IR::Graph;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Multiply;

# Test 1: Basic operation pulling with Add
subtest 'Phi operation pulling: Phi(region, Add(a,b), Add(c,d)) -> Add(Phi(a,c), Phi(b,d))' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Region node with two control inputs
    my $region = Chalk::IR::Node::Region->new(
        inputs => [0, 0],  # Two control inputs
    );
    $graph->add_node($region);

    # Create constants for Add inputs
    my $a = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $b = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $c = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $d = Chalk::IR::Node::Constant->new(value => 4, type => 'Integer');
    $graph->add_node($a);
    $graph->add_node($b);
    $graph->add_node($c);
    $graph->add_node($d);

    # Create Add nodes: Add(a, b) and Add(c, d)
    my $add1 = Chalk::IR::Node::Add->new(left => $a, right => $b);
    my $add2 = Chalk::IR::Node::Add->new(left => $c, right => $d);
    $graph->add_node($add1);
    $graph->add_node($add2);

    # Create Phi with both Add nodes as data inputs
    # Phi inputs: [region_id, value1, value2]
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $add1->id, $add2->id],
    );
    $graph->add_node($phi);

    # Apply peephole optimization
    my $optimized = $phi->peephole($graph);

    # Should be transformed to Add(Phi(a,c), Phi(b,d))
    is($optimized->op, 'Add', 'Result is Add node (operation pulled out)');
    isnt($optimized->id, $phi->id, 'A new node was created');

    # The Add's inputs should be Phi nodes
    # Note: Add node stores left/right as node references, not IDs
    ok($optimized->left, 'Add has left operand');
    ok($optimized->right, 'Add has right operand');
    is($optimized->left->op, 'Phi', 'Left operand is Phi');
    is($optimized->right->op, 'Phi', 'Right operand is Phi');
};

# Test 2: No pulling when operations differ
subtest 'Phi does NOT pull when operations differ' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $region = Chalk::IR::Node::Region->new(
        inputs => [0, 0],
    );
    $graph->add_node($region);

    my $a = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $b = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $c = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $d = Chalk::IR::Node::Constant->new(value => 4, type => 'Integer');
    $graph->add_node($a);
    $graph->add_node($b);
    $graph->add_node($c);
    $graph->add_node($d);

    # Create Add and Multiply nodes (different operations)
    my $add = Chalk::IR::Node::Add->new(left => $a, right => $b);
    my $mul = Chalk::IR::Node::Multiply->new(left => $c, right => $d);
    $graph->add_node($add);
    $graph->add_node($mul);

    # Create Phi with different operation types
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $add->id, $mul->id],
    );
    $graph->add_node($phi);

    my $optimized = $phi->peephole($graph);

    # Should NOT transform - operations differ
    is($optimized->op, 'Phi', 'Phi preserved when ops differ');
    is($optimized->id, $phi->id, 'Same Phi node returned');
};

# Test 3: No pulling when one input is a constant (different op)
subtest 'Phi does NOT pull when input types differ' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $region = Chalk::IR::Node::Region->new(
        inputs => [0, 0],
    );
    $graph->add_node($region);

    my $a = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $b = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $c = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    $graph->add_node($a);
    $graph->add_node($b);
    $graph->add_node($c);

    my $add = Chalk::IR::Node::Add->new(left => $a, right => $b);
    $graph->add_node($add);

    # Phi with Add and Constant (different op types)
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $add->id, $c->id],
    );
    $graph->add_node($phi);

    my $optimized = $phi->peephole($graph);

    # Should NOT transform
    is($optimized->op, 'Phi', 'Phi preserved when input types differ');
};

# Test 4: Pulling with Multiply operations
subtest 'Phi operation pulling works with Multiply' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $region = Chalk::IR::Node::Region->new(
        inputs => [0, 0],
    );
    $graph->add_node($region);

    my $a = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $b = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $c = Chalk::IR::Node::Constant->new(value => 4, type => 'Integer');
    my $d = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    $graph->add_node($a);
    $graph->add_node($b);
    $graph->add_node($c);
    $graph->add_node($d);

    my $mul1 = Chalk::IR::Node::Multiply->new(left => $a, right => $b);
    my $mul2 = Chalk::IR::Node::Multiply->new(left => $c, right => $d);
    $graph->add_node($mul1);
    $graph->add_node($mul2);

    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $mul1->id, $mul2->id],
    );
    $graph->add_node($phi);

    my $optimized = $phi->peephole($graph);

    is($optimized->op, 'Multiply', 'Result is Multiply node');
    is($optimized->left->op, 'Phi', 'Left operand is Phi');
    is($optimized->right->op, 'Phi', 'Right operand is Phi');
};

# Test 5: No pulling from Loop-based Phis (loop phis have different semantics)
subtest 'Phi does NOT pull from Loop-based Phi' => sub {
    my $graph = Chalk::IR::Graph->new();

    # Loop node instead of Region
    my $loop = Chalk::IR::Node->new(
        id => 'loop_1',
        op => 'Loop',
        inputs => [0],
        attributes => {},
    );
    $graph->add_node($loop);

    my $a = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $b = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $c = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $d = Chalk::IR::Node::Constant->new(value => 4, type => 'Integer');
    $graph->add_node($a);
    $graph->add_node($b);
    $graph->add_node($c);
    $graph->add_node($d);

    my $add1 = Chalk::IR::Node::Add->new(left => $a, right => $b);
    my $add2 = Chalk::IR::Node::Add->new(left => $c, right => $d);
    $graph->add_node($add1);
    $graph->add_node($add2);

    # Phi with Loop as control
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $loop->id,
        inputs => [$loop->id, $add1->id, $add2->id],
    );
    $graph->add_node($phi);

    my $optimized = $phi->peephole($graph);

    # Should NOT transform Loop-based phis
    is($optimized->op, 'Phi', 'Loop Phi preserved');
    is($optimized->id, $phi->id, 'Same Phi node returned for Loop');
};

# Test 6: Three-way Region with same operations
subtest 'Phi operation pulling with three inputs' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $region = Chalk::IR::Node::Region->new(
        inputs => [0, 0, 0],  # Three control inputs
    );
    $graph->add_node($region);

    my $a = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $b = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    my $c = Chalk::IR::Node::Constant->new(value => 3, type => 'Integer');
    my $d = Chalk::IR::Node::Constant->new(value => 4, type => 'Integer');
    my $e = Chalk::IR::Node::Constant->new(value => 5, type => 'Integer');
    my $f = Chalk::IR::Node::Constant->new(value => 6, type => 'Integer');
    $graph->add_node($a);
    $graph->add_node($b);
    $graph->add_node($c);
    $graph->add_node($d);
    $graph->add_node($e);
    $graph->add_node($f);

    my $add1 = Chalk::IR::Node::Add->new(left => $a, right => $b);
    my $add2 = Chalk::IR::Node::Add->new(left => $c, right => $d);
    my $add3 = Chalk::IR::Node::Add->new(left => $e, right => $f);
    $graph->add_node($add1);
    $graph->add_node($add2);
    $graph->add_node($add3);

    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $add1->id, $add2->id, $add3->id],
    );
    $graph->add_node($phi);

    my $optimized = $phi->peephole($graph);

    is($optimized->op, 'Add', 'Result is Add node with 3 inputs');
    is($optimized->left->op, 'Phi', 'Left operand is Phi');
    is($optimized->right->op, 'Phi', 'Right operand is Phi');
};

# Test 7: Single data input - no pulling needed (singleUniqueInput handles this)
subtest 'Phi with single data input uses singleUniqueInput optimization instead' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $region = Chalk::IR::Node::Region->new(
        inputs => [0],  # Single control input
    );
    $graph->add_node($region);

    my $a = Chalk::IR::Node::Constant->new(value => 1, type => 'Integer');
    my $b = Chalk::IR::Node::Constant->new(value => 2, type => 'Integer');
    $graph->add_node($a);
    $graph->add_node($b);

    my $add = Chalk::IR::Node::Add->new(left => $a, right => $b);
    $graph->add_node($add);

    # Phi with single data input
    my $phi = Chalk::IR::Node::Phi->new(
        region_id => $region->id,
        inputs => [$region->id, $add->id],
    );
    $graph->add_node($phi);

    my $optimized = $phi->peephole($graph);

    # singleUniqueInput should simplify to the single Add input
    is($optimized->id, $add->id, 'Single input Phi simplifies to the input');
};
