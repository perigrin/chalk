#!/usr/bin/env perl
# ABOUTME: Test systematic loop-carried dependency tracking with phi nodes
# ABOUTME: Validates Builder methods for tracking and generating loop phi nodes with Context model

use lib 'lib';
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Builder;
use Chalk::IR::Graph;
use Chalk::IR::Context;

subtest 'Context stores variables with lexical namespace' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    # Store some variables
    my $const_1 = $builder->build_constant_node(1);
    my $const_2 = $builder->build_constant_node(2);
    my $const_3 = $builder->build_constant_node(3);

    $builder->build_store_node('x', $const_1);
    $builder->build_store_node('y', $const_2);
    $builder->build_store_node('z', $const_3);

    # Verify we can retrieve them
    my $x = $builder->context->('lexical:x');
    my $y = $builder->context->('lexical:y');
    my $z = $builder->context->('lexical:z');

    ok defined($x), 'Variable x stored in context';
    ok defined($y), 'Variable y stored in context';
    ok defined($z), 'Variable z stored in context';
    is $x->id, $const_1->id, 'Variable x has correct value';
    is $y->id, $const_2->id, 'Variable y has correct value';
    is $z->id, $const_3->id, 'Variable z has correct value';
};

subtest 'Builder tracks modified variables in loops' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    # Define variables before loop
    my $const_1 = $builder->build_constant_node(1);
    my $const_2 = $builder->build_constant_node(2);
    $builder->build_store_node('i', $const_1);
    $builder->build_store_node('limit', $const_2);

    # Start tracking loop
    $builder->begin_loop_tracking();

    # Modify only $i inside the loop
    my $const_3 = $builder->build_constant_node(3);
    $builder->build_store_node('i', $const_3);

    # Verify tracking is active
    ok $builder->is_tracking_loop(), 'Loop tracking active';

    # Create loop and generate phis
    my $loop = $builder->build_loop_node();
    my $phis = $builder->generate_loop_phi_nodes($loop);

    # Should have phi for modified variable i
    ok exists($phis->{i}), 'Phi generated for modified variable i';
    ok !exists($phis->{limit}), 'No phi for unmodified variable limit';
};

subtest 'Builder generates phi nodes with correct structure' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    # Setup: Define variables before loop
    my $const_0 = $builder->build_constant_node(0);
    my $const_1 = $builder->build_constant_node(1);
    $builder->build_store_node('i', $const_0);
    $builder->build_store_node('sum', $const_1);

    # Start tracking loop
    $builder->begin_loop_tracking();

    # Create loop node
    my $loop = $builder->build_loop_node();

    # Simulate modifications within loop body
    my $i_update = $builder->build_add_node($const_0, $const_1);
    my $sum_update = $builder->build_add_node($const_1, $const_0);
    $builder->build_store_node('i', $i_update);
    $builder->build_store_node('sum', $sum_update);

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

subtest 'End loop tracking cleans up state' => sub {
    my $builder = Chalk::IR::Builder->new();

    $builder->begin_loop_tracking();
    ok $builder->is_tracking_loop(), 'Tracking active';

    $builder->end_loop_tracking();
    ok !$builder->is_tracking_loop(), 'Tracking ended';
};

subtest 'Builder creates phi with complete backedge' => sub {
    my $builder = Chalk::IR::Builder->new();
    my $start = $builder->build_start_node();

    my $const_0 = $builder->build_constant_node(0);
    $builder->build_store_node('i', $const_0);

    $builder->begin_loop_tracking();
    my $loop = $builder->build_loop_node();

    # Modify variable
    my $i_update = $builder->build_constant_node(5);
    $builder->build_store_node('i', $i_update);

    # Generate phi - automatically captures backedge
    my $phis = $builder->generate_loop_phi_nodes($loop);
    my $phi = $phis->{i};

    # Verify phi has all three inputs
    is scalar($phi->inputs->@*), 3, 'Phi has control, initial, and backedge';
    is $phi->inputs->[0], $loop->id, 'First input is loop control';
    is $phi->inputs->[1], $const_0->id, 'Second input is initial value';
    is $phi->inputs->[2], $i_update->id, 'Third input is loop backedge value';
};
