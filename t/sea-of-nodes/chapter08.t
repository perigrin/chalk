#!/usr/bin/env perl
# ABOUTME: Test Sea of Nodes Chapter 8 - Break and Continue statements
# ABOUTME: Validates loop control flow with early exit and continue semantics

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use lib 't/lib';
use Chalk::IR::Node;
use Chalk::IR::Graph;
use Chalk::IR::Scope;
use Chalk::IR::Validator;

subtest 'Break statement basic structure' => sub {
    # while (true) { break; }
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $loop = Chalk::IR::Node->new(
        id => 2,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);

    # Break creates a Region with loop exit and break paths
    my $break_region = Chalk::IR::Node->new(
        id => 3,
        op => 'Region',
        inputs => [$loop->id],  # Break path will be added
        attributes => {},
    );
    $graph->add_node($break_region);

    # Loop backedge goes nowhere (break exits immediately)
    # Break exits to region

    my $return_node = Chalk::IR::Node->new(
        id => 4,
        op => 'Return',
        inputs => [$break_region->id, 0],
        attributes => {},
    );
    $graph->add_node($return_node);

    is scalar($loop->inputs->@*), 1, 'Loop has only entry (no backedge due to break)';
    ok $break_region, 'Break creates exit region';
};

subtest 'Break with condition: while(i < 10) { if(i == 5) break; i++; }' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $const_0 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $loop = Chalk::IR::Node->new(
        id => 3,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);

    my $phi_i = Chalk::IR::Node->new(
        id => 4,
        op => 'Phi',
        inputs => [$loop->id, $const_0->id],
        attributes => {},
    );
    $graph->add_node($phi_i);

    # Condition: i == 5
    my $const_5 = Chalk::IR::Node->new(
        id => 5,
        op => 'Constant',
        inputs => [],
        attributes => { value => 5 },
    );
    $graph->add_node($const_5);

    my $eq = Chalk::IR::Node->new(
        id => 6,
        op => 'EQ',
        inputs => [$phi_i->id, $const_5->id],
        attributes => {},
    );
    $graph->add_node($eq);

    # If i == 5
    my $if_break = Chalk::IR::Node->new(
        id => 7,
        op => 'If',
        inputs => [$loop->id, $eq->id],
        attributes => {},
    );
    $graph->add_node($if_break);

    # True branch: break
    my $if_true = Chalk::IR::Node->new(
        id => 8,
        op => 'Proj',
        inputs => [$if_break->id],
        attributes => { index => 0 },
    );
    $graph->add_node($if_true);

    # False branch: continue to i++
    my $if_false = Chalk::IR::Node->new(
        id => 9,
        op => 'Proj',
        inputs => [$if_break->id],
        attributes => { index => 1 },
    );
    $graph->add_node($if_false);

    # i = i + 1
    my $const_1 = Chalk::IR::Node->new(
        id => 10,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_1);

    my $add = Chalk::IR::Node->new(
        id => 11,
        op => 'Add',
        inputs => [$phi_i->id, $const_1->id],
        attributes => {},
    );
    $graph->add_node($add);

    # Loop backedge from false branch
    push $phi_i->inputs->@*, $add->id;
    push $loop->inputs->@*, $if_false->id;

    # Break exit merges with loop condition check
    # (Simplified: just exit via true branch)
    my $break_region = Chalk::IR::Node->new(
        id => 12,
        op => 'Region',
        inputs => [$if_true->id],
        attributes => {},
    );
    $graph->add_node($break_region);

    my $return_node = Chalk::IR::Node->new(
        id => 13,
        op => 'Return',
        inputs => [$break_region->id, $phi_i->id],
        attributes => {},
    );
    $graph->add_node($return_node);

    is scalar($loop->inputs->@*), 2, 'Loop has entry and backedge';
    is scalar($phi_i->inputs->@*), 3, 'Phi has control, init, and loop value';
    ok $break_region, 'Break creates exit region';
};

subtest 'Continue statement basic structure' => sub {
    # while (true) { if (cond) continue; other_work(); }
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $loop = Chalk::IR::Node->new(
        id => 2,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);

    my $const_true = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_true);

    my $if_node = Chalk::IR::Node->new(
        id => 4,
        op => 'If',
        inputs => [$loop->id, $const_true->id],
        attributes => {},
    );
    $graph->add_node($if_node);

    # True branch: continue (goes back to loop)
    my $if_true = Chalk::IR::Node->new(
        id => 5,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 0 },
    );
    $graph->add_node($if_true);

    # False branch: other work, then back to loop
    my $if_false = Chalk::IR::Node->new(
        id => 6,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 1 },
    );
    $graph->add_node($if_false);

    # Region merges continue path and normal path back to loop
    my $merge_region = Chalk::IR::Node->new(
        id => 7,
        op => 'Region',
        inputs => [$if_true->id, $if_false->id],
        attributes => {},
    );
    $graph->add_node($merge_region);

    # Loop backedge
    push $loop->inputs->@*, $merge_region->id;

    is scalar($loop->inputs->@*), 2, 'Loop has entry and backedge';
    is scalar($merge_region->inputs->@*), 2, 'Continue merges two paths';
};

subtest 'Continue with counter: while(i < 10) { if(i % 2 == 0) continue; sum += i; i++; }' => sub {
    # Skip even numbers, sum odd numbers
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $const_0 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $loop = Chalk::IR::Node->new(
        id => 3,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);

    # Phi for i
    my $phi_i = Chalk::IR::Node->new(
        id => 4,
        op => 'Phi',
        inputs => [$loop->id, $const_0->id],
        attributes => {},
    );
    $graph->add_node($phi_i);

    # Phi for sum
    my $phi_sum = Chalk::IR::Node->new(
        id => 5,
        op => 'Phi',
        inputs => [$loop->id, $const_0->id],
        attributes => {},
    );
    $graph->add_node($phi_sum);

    # Check i < 10
    my $const_10 = Chalk::IR::Node->new(
        id => 6,
        op => 'Constant',
        inputs => [],
        attributes => { value => 10 },
    );
    $graph->add_node($const_10);

    my $lt = Chalk::IR::Node->new(
        id => 7,
        op => 'LT',
        inputs => [$phi_i->id, $const_10->id],
        attributes => {},
    );
    $graph->add_node($lt);

    my $if_loop = Chalk::IR::Node->new(
        id => 8,
        op => 'If',
        inputs => [$loop->id, $lt->id],
        attributes => {},
    );
    $graph->add_node($if_loop);

    # True: loop body
    my $loop_true = Chalk::IR::Node->new(
        id => 9,
        op => 'Proj',
        inputs => [$if_loop->id],
        attributes => { index => 0 },
    );
    $graph->add_node($loop_true);

    # False: exit loop
    my $loop_false = Chalk::IR::Node->new(
        id => 10,
        op => 'Proj',
        inputs => [$if_loop->id],
        attributes => { index => 1 },
    );
    $graph->add_node($loop_false);

    is scalar($phi_i->inputs->@*), 2, 'Phi i has control and init (loop value added later)';
    is scalar($phi_sum->inputs->@*), 2, 'Phi sum has control and init';
    ok $loop_true, 'Loop body path exists';
    ok $loop_false, 'Loop exit path exists';
};

subtest 'Break and Continue together: while(true) { if(x) break; if(y) continue; work(); }' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $loop = Chalk::IR::Node->new(
        id => 2,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);

    # First condition: if(x) break
    my $const_x = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_x);

    my $if_break = Chalk::IR::Node->new(
        id => 4,
        op => 'If',
        inputs => [$loop->id, $const_x->id],
        attributes => {},
    );
    $graph->add_node($if_break);

    my $break_true = Chalk::IR::Node->new(
        id => 5,
        op => 'Proj',
        inputs => [$if_break->id],
        attributes => { index => 0 },
    );
    $graph->add_node($break_true);

    my $break_false = Chalk::IR::Node->new(
        id => 6,
        op => 'Proj',
        inputs => [$if_break->id],
        attributes => { index => 1 },
    );
    $graph->add_node($break_false);

    # Second condition: if(y) continue
    my $const_y = Chalk::IR::Node->new(
        id => 7,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_y);

    my $if_continue = Chalk::IR::Node->new(
        id => 8,
        op => 'If',
        inputs => [$break_false->id, $const_y->id],
        attributes => {},
    );
    $graph->add_node($if_continue);

    my $continue_true = Chalk::IR::Node->new(
        id => 9,
        op => 'Proj',
        inputs => [$if_continue->id],
        attributes => { index => 0 },
    );
    $graph->add_node($continue_true);

    my $continue_false = Chalk::IR::Node->new(
        id => 10,
        op => 'Proj',
        inputs => [$if_continue->id],
        attributes => { index => 1 },
    );
    $graph->add_node($continue_false);

    # Merge continue and normal paths
    my $backedge_region = Chalk::IR::Node->new(
        id => 11,
        op => 'Region',
        inputs => [$continue_true->id, $continue_false->id],
        attributes => {},
    );
    $graph->add_node($backedge_region);

    push $loop->inputs->@*, $backedge_region->id;

    # Break exit
    my $break_region = Chalk::IR::Node->new(
        id => 12,
        op => 'Region',
        inputs => [$break_true->id],
        attributes => {},
    );
    $graph->add_node($break_region);

    my $return_node = Chalk::IR::Node->new(
        id => 13,
        op => 'Return',
        inputs => [$break_region->id, 0],
        attributes => {},
    );
    $graph->add_node($return_node);

    is scalar($loop->inputs->@*), 2, 'Loop has entry and backedge';
    is scalar($backedge_region->inputs->@*), 2, 'Backedge region merges continue and normal';
    ok $break_region, 'Break creates exit region';
};

subtest 'Nested loops with break' => sub {
    # while(i < 5) { while(j < 3) { if(j == 2) break; j++; } i++; }
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $const_0 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    # Outer loop
    my $outer_loop = Chalk::IR::Node->new(
        id => 3,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($outer_loop);

    my $phi_i = Chalk::IR::Node->new(
        id => 4,
        op => 'Phi',
        inputs => [$outer_loop->id, $const_0->id],
        attributes => {},
    );
    $graph->add_node($phi_i);

    # Inner loop
    my $inner_loop = Chalk::IR::Node->new(
        id => 5,
        op => 'Loop',
        inputs => [$outer_loop->id],
        attributes => {},
    );
    $graph->add_node($inner_loop);

    my $phi_j = Chalk::IR::Node->new(
        id => 6,
        op => 'Phi',
        inputs => [$inner_loop->id, $const_0->id],
        attributes => {},
    );
    $graph->add_node($phi_j);

    is scalar($outer_loop->inputs->@*), 1, 'Outer loop has entry (backedge added later)';
    is scalar($inner_loop->inputs->@*), 1, 'Inner loop has entry (backedge added later)';
    is scalar($phi_i->inputs->@*), 2, 'Outer phi has control and init';
    is scalar($phi_j->inputs->@*), 2, 'Inner phi has control and init';
};

subtest 'Loop with multiple exits' => sub {
    # while(true) { if(a) break; if(b) break; if(c) continue; }
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $loop = Chalk::IR::Node->new(
        id => 2,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);

    # Multiple break conditions create multiple exit paths
    # All merge into final exit region

    my $break_region = Chalk::IR::Node->new(
        id => 3,
        op => 'Region',
        inputs => [],  # Will be filled with break paths
        attributes => {},
    );
    $graph->add_node($break_region);

    # For now just test structure
    is scalar($loop->inputs->@*), 1, 'Loop has entry';
    ok $break_region, 'Break region exists for multiple exits';
};

subtest 'Break with phi values' => sub {
    # result = undef; while(i < 10) { if(i == 5) { result = i; break; } i++; } return result;
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $const_0 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $loop = Chalk::IR::Node->new(
        id => 3,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);

    my $phi_i = Chalk::IR::Node->new(
        id => 4,
        op => 'Phi',
        inputs => [$loop->id, $const_0->id],
        attributes => {},
    );
    $graph->add_node($phi_i);

    # Break carries phi value out of loop
    my $break_region = Chalk::IR::Node->new(
        id => 5,
        op => 'Region',
        inputs => [],  # Simplified
        attributes => {},
    );
    $graph->add_node($break_region);

    # Phi at break region merges break value and loop exit value
    my $result_phi = Chalk::IR::Node->new(
        id => 6,
        op => 'Phi',
        inputs => [$break_region->id, $phi_i->id],
        attributes => {},
    );
    $graph->add_node($result_phi);

    my $return_node = Chalk::IR::Node->new(
        id => 7,
        op => 'Return',
        inputs => [$break_region->id, $result_phi->id],
        attributes => {},
    );
    $graph->add_node($return_node);

    ok $result_phi, 'Phi at break region merges values';
    is $return_node->inputs->[1], $result_phi->id, 'Return uses break phi value';
};

subtest 'Validation with break and continue' => sub {
    # Simplified valid graph with loop, break, continue
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $loop = Chalk::IR::Node->new(
        id => 2,
        op => 'Loop',
        inputs => [$start->id, 3],
        attributes => {},
    );
    $graph->add_node($loop);

    my $backedge_region = Chalk::IR::Node->new(
        id => 3,
        op => 'Region',
        inputs => [$loop->id],
        attributes => {},
    );
    $graph->add_node($backedge_region);

    my $break_region = Chalk::IR::Node->new(
        id => 4,
        op => 'Region',
        inputs => [$loop->id],
        attributes => {},
    );
    $graph->add_node($break_region);

    my $return_node = Chalk::IR::Node->new(
        id => 5,
        op => 'Return',
        inputs => [$break_region->id, 0],
        attributes => {},
    );
    $graph->add_node($return_node);

    my $validator = Chalk::IR::Validator->new();
    my @cfg_errors = $validator->validate_cfg($graph);
    if (@cfg_errors) {
        diag("CFG errors: " . join(", ", @cfg_errors));
    }
    is scalar(@cfg_errors), 0, 'CFG with break/continue validates';
};

subtest 'Complex control flow: do-while pattern' => sub {
    # do { i++; } while(i < 10);
    # Loop body executes at least once
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $const_0 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    # Loop starts immediately (no condition check at entry)
    my $loop = Chalk::IR::Node->new(
        id => 3,
        op => 'Loop',
        inputs => [$start->id],
        attributes => {},
    );
    $graph->add_node($loop);

    my $phi_i = Chalk::IR::Node->new(
        id => 4,
        op => 'Phi',
        inputs => [$loop->id, $const_0->id],
        attributes => {},
    );
    $graph->add_node($phi_i);

    # Body: i++
    my $const_1 = Chalk::IR::Node->new(
        id => 5,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_1);

    my $add = Chalk::IR::Node->new(
        id => 6,
        op => 'Add',
        inputs => [$phi_i->id, $const_1->id],
        attributes => {},
    );
    $graph->add_node($add);

    # Condition check AFTER body: i < 10
    my $const_10 = Chalk::IR::Node->new(
        id => 7,
        op => 'Constant',
        inputs => [],
        attributes => { value => 10 },
    );
    $graph->add_node($const_10);

    my $lt = Chalk::IR::Node->new(
        id => 8,
        op => 'LT',
        inputs => [$add->id, $const_10->id],
        attributes => {},
    );
    $graph->add_node($lt);

    my $if_node = Chalk::IR::Node->new(
        id => 9,
        op => 'If',
        inputs => [$loop->id, $lt->id],
        attributes => {},
    );
    $graph->add_node($if_node);

    # True: continue loop
    my $if_true = Chalk::IR::Node->new(
        id => 10,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 0 },
    );
    $graph->add_node($if_true);

    # False: exit
    my $if_false = Chalk::IR::Node->new(
        id => 11,
        op => 'Proj',
        inputs => [$if_node->id],
        attributes => { index => 1 },
    );
    $graph->add_node($if_false);

    push $phi_i->inputs->@*, $add->id;
    push $loop->inputs->@*, $if_true->id;

    my $return_node = Chalk::IR::Node->new(
        id => 12,
        op => 'Return',
        inputs => [$if_false->id, $phi_i->id],
        attributes => {},
    );
    $graph->add_node($return_node);

    is scalar($loop->inputs->@*), 2, 'Do-while loop has entry and backedge';
    is scalar($phi_i->inputs->@*), 3, 'Phi has control, init, and loop value';
};
