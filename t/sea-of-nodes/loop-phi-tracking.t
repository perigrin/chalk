#!/usr/bin/env perl
# ABOUTME: Test systematic loop-carried dependency tracking with phi nodes
# ABOUTME: Validates Builder methods for tracking and generating loop phi nodes

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::IR::Builder;
use Chalk::IR::Graph;
use Chalk::IR::Scope;

subtest 'Scope can snapshot bindings before loop' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $scope = $builder->scope;

    # Define some variables
    $scope->define('x', 'node_1');
    $scope->define('y', 'node_2');
    $scope->define('z', 'node_3');

    # Take a snapshot
    my $snapshot = $scope->snapshot_bindings();

    ok $snapshot, 'Can create binding snapshot';
    is ref($snapshot), 'HASH', 'Snapshot is a hashref';
    is $snapshot->{x}, 'node_1', 'Snapshot captures x binding';
    is $snapshot->{y}, 'node_2', 'Snapshot captures y binding';
    is $snapshot->{z}, 'node_3', 'Snapshot captures z binding';
};

subtest 'Scope can detect modified variables' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $scope = $builder->scope;

    # Initial bindings
    $scope->define('i', 'node_1');
    $scope->define('limit', 'node_2');

    my $snapshot = $scope->snapshot_bindings();

    # Modify $i
    $scope->define('i', 'node_3');

    # Detect changes
    my @modified = $scope->find_modified_variables($snapshot);

    is scalar(@modified), 1, 'One variable modified';
    is $modified[0], 'i', 'Variable i was modified';
};

subtest 'Builder tracks loop entry scope' => sub {
    my $builder = Chalk::IR::Builder->new();

    # Define variables before loop
    $builder->scope->define('i', 'initial_i');
    $builder->scope->define('sum', 'initial_sum');

    # Start tracking loop
    $builder->begin_loop_tracking();

    ok $builder->is_tracking_loop(), 'Loop tracking active';

    # Get snapshot
    my $entry_scope = $builder->loop_entry_scope();
    ok $entry_scope, 'Entry scope captured';
    is $entry_scope->{i}, 'initial_i', 'Initial binding for i captured';
};

subtest 'Builder generates phi nodes for modified variables' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $scope = $builder->scope;

    # Setup: Define variables before loop
    my $const_0 = $builder->build_constant_node(0);
    my $const_1 = $builder->build_constant_node(1);
    $scope->define('i', $const_0->id);
    $scope->define('sum', $const_1->id);

    # Start tracking loop
    $builder->begin_loop_tracking();

    # Create loop node
    my $start = $builder->build_start_node();
    my $loop = $builder->build_loop_node();

    # Simulate modifications within loop body
    my $i_update = $builder->build_add_node($const_0, $const_1);
    my $sum_update = $builder->build_add_node($const_1, $const_0);
    $scope->define('i', $i_update->id);
    $scope->define('sum', $sum_update->id);

    # Generate phi nodes for modified variables
    my $phis = $builder->generate_loop_phi_nodes($loop);

    ok $phis, 'Phi nodes generated';
    is ref($phis), 'HASH', 'Returns hashref of variable -> phi_node';
    ok exists($phis->{i}), 'Phi generated for modified variable i';
    ok exists($phis->{sum}), 'Phi generated for modified variable sum';

    # Verify phi structure
    my $phi_i = $phis->{i};
    is $phi_i->op, 'Phi', 'Generated node is a Phi';
    is $phi_i->inputs->[0], $loop->id, 'Phi control is loop node';
};

subtest 'Unmodified variables do not generate phis' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $scope = $builder->scope;

    # Setup
    my $const_0 = $builder->build_constant_node(0);
    my $const_10 = $builder->build_constant_node(10);
    $scope->define('i', $const_0->id);
    $scope->define('limit', $const_10->id);  # Not modified

    $builder->begin_loop_tracking();
    my $loop = $builder->build_loop_node();

    # Only modify i
    my $i_update = $builder->build_add_node($const_0, $const_0);
    $scope->define('i', $i_update->id);

    my $phis = $builder->generate_loop_phi_nodes($loop);

    ok exists($phis->{i}), 'Phi for modified variable i';
    ok !exists($phis->{limit}), 'No phi for unmodified variable limit';
};

subtest 'End loop tracking cleans up state' => sub {
    my $builder = Chalk::IR::Builder->new();

    $builder->begin_loop_tracking();
    ok $builder->is_tracking_loop(), 'Tracking active';

    $builder->end_loop_tracking();
    ok !$builder->is_tracking_loop(), 'Tracking ended';
};

subtest 'Builder creates phi with complete backedge' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $scope = $builder->scope;

    my $const_0 = $builder->build_constant_node(0);
    $scope->define('i', $const_0->id);

    $builder->begin_loop_tracking();
    my $loop = $builder->build_loop_node();

    # Modify variable
    my $i_update = $builder->build_constant_node(5);
    $scope->define('i', $i_update->id);

    # Generate phi - automatically captures backedge
    my $phis = $builder->generate_loop_phi_nodes($loop);
    my $phi = $phis->{i};

    # Verify phi has all three inputs
    is scalar($phi->inputs->@*), 3, 'Phi has control, initial, and backedge';
    is $phi->inputs->[0], $loop->id, 'First input is loop control';
    is $phi->inputs->[1], $const_0->id, 'Second input is initial value';
    is $phi->inputs->[2], $i_update->id, 'Third input is loop backedge value';
};
