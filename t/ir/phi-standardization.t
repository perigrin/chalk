#!/usr/bin/env perl
# ABOUTME: Test that Phi nodes use standardized inputs array representation
# ABOUTME: Verifies peephole optimizer and validator both use inputs array (not alternatives attribute)

use v5.42;
use Test::More;
use lib 'lib';
use Chalk::IR::Graph;
use Chalk::IR::Node;
use Chalk::IR::Validator;

# Test that peephole optimizer correctly processes Phi nodes using inputs array
# This test ensures the fix for GitHub Issue #80 works correctly

# TODO: This test is currently expected to fail - it documents GitHub Issue #80
# The peephole optimizer needs to be fixed to read from inputs array
TODO: {
    local $TODO = "Peephole optimizer doesn't yet optimize Phi nodes with dead paths (GitHub Issue #80)";

subtest 'Phi node with dead control path uses inputs array' => sub {
    my $graph = Chalk::IR::Graph->new;

    # Create Start node
    my $start = Chalk::IR::Node->new(
        id => 'start',
        op => 'Start',
        inputs => [],
        attributes => {}
    );
    $graph->add_node($start);

    # Create constants for alternative values
    my $const_true = Chalk::IR::Node->new(
        id => 'const_42',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42 }
    );
    $graph->add_node($const_true);

    my $const_false = Chalk::IR::Node->new(
        id => 'const_0',
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 }
    );
    $graph->add_node($const_false);

    # Create dead control marker
    my $dead_ctrl = Chalk::IR::Node->new(
        id => 'dead_ctrl',
        op => 'Constant',
        inputs => [],
        attributes => { value => '~Ctrl' }
    );
    $graph->add_node($dead_ctrl);

    # Create Region with one dead path
    my $region = Chalk::IR::Node->new(
        id => 'region',
        op => 'Region',
        inputs => ['start', 'dead_ctrl'],  # second input is dead
        attributes => {}
    );
    $graph->add_node($region);

    # Create Phi node using ONLY inputs array (standardized representation)
    # This is the correct way - no 'alternatives' attribute
    # Use from_hash to get proper polymorphic Chalk::IR::Node::Phi object
    my $phi = Chalk::IR::Node->from_hash({
        id => 'phi',
        op => 'Phi',
        inputs => ['region', 'const_42', 'const_0'],  # control, then alternatives
        attributes => { region_id => 'region' }
    });
    $graph->add_node($phi);

    # Run peephole optimization on the Phi node
    my $optimized_phi = $phi->peephole($graph);

    # The optimizer should detect the dead path and simplify the Phi
    # If it only checks 'alternatives' attribute, it will NOT optimize (current bug)
    # After fix, it should read from inputs array and reduce to const_42
    ok(defined($optimized_phi), 'Peephole optimizer should process Phi node');

    # Before the fix, this will fail because peephole only checks alternatives attribute
    # After the fix, the Phi should be replaced with the single live alternative (const_42)
    if ($optimized_phi->op eq 'Constant') {
        is($optimized_phi->attributes->{value}, 42,
           'Phi with one dead path should be optimized to live alternative (42)');
    } else {
        # If not optimized to constant, the test reveals the bug
        fail('Phi should have been optimized to constant when only one path is live');
        diag('This indicates peephole optimizer is not reading from inputs array');
    }
};
}  # End TODO block

subtest 'Validator rejects Phi with mismatched inputs and region' => sub {
    my $graph = Chalk::IR::Graph->new;

    # Create Start node
    my $start = Chalk::IR::Node->new(
        id => 'start',
        op => 'Start',
        inputs => [],
        attributes => {}
    );
    $graph->add_node($start);

    # Create a second control node
    my $start2 = Chalk::IR::Node->new(
        id => 'start2',
        op => 'Start',
        inputs => [],
        attributes => {}
    );
    $graph->add_node($start2);

    # Create constant
    my $const = Chalk::IR::Node->new(
        id => 'const_42',
        op => 'Constant',
        inputs => [],
        attributes => { value => 42 }
    );
    $graph->add_node($const);

    # Create Region with 2 inputs
    my $region = Chalk::IR::Node->new(
        id => 'region',
        op => 'Region',
        inputs => ['start', 'start2'],
        attributes => {}
    );
    $graph->add_node($region);

    # Create Phi with wrong number of alternatives (only 1, should be 2)
    my $phi = Chalk::IR::Node->new(
        id => 'phi',
        op => 'Phi',
        inputs => ['region', 'const_42'],  # Only 1 alternative, but Region has 2 predecessors
        attributes => { region_id => 'region' }
    );
    $graph->add_node($phi);

    # Validator should detect mismatch by checking inputs array
    my $validator = Chalk::IR::Validator->new;
    my @errors = $validator->validate_phi_placement($graph);
    ok(scalar(@errors) > 0, 'Validator should detect Phi/Region mismatch using inputs array')
        or diag("Expected validation error but got none");

    like($errors[0] // '', qr/expects 2 value inputs.*but has 1/i,
         'Error message should indicate wrong number of alternatives');
};

done_testing;
