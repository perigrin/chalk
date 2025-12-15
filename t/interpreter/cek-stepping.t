#!/usr/bin/env perl
# ABOUTME: Tests CEK interpreter step-by-step execution mode and state inspection
# ABOUTME: Verifies initialization, stepping through computation, state queries, and equivalence with execute() mode
use 5.42.0;
use lib 'lib';
use Test::More tests => 24;
use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Return;
use Chalk::IR::Type::Integer;
use Chalk::Interpreter::CEKDataflow;

# Test 1-2: Basic stepping initialization
my $graph1 = Chalk::IR::Graph->new();
my $start1 = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
my $const1 = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->TOP());
my $const2 = Chalk::IR::Node::Constant->new(value => 3, type => Chalk::IR::Type::Integer->TOP());
my $add = Chalk::IR::Node::Add->new(left => $const1, right => $const2);
my $ret = Chalk::IR::Node::Return->new(
    control => $start1,
    value => $add,
);

$graph1->add_node($start1);
$graph1->add_node($const1);
$graph1->add_node($const2);
$graph1->add_node($add);
$graph1->add_node($ret);

my $interp1 = Chalk::Interpreter::CEKDataflow->new(graph => $graph1);
$interp1->initialize_stepping();

ok(!$interp1->is_stepping_complete(), "Stepping not complete after initialization");

my $state1 = $interp1->get_step_state();
is(scalar(@{$state1->{ready_queue}}), 3, "Three nodes ready initially (Start and both constants)");

# Test 3-8: Step through execution
# First three steps include Start and both constants (in any order)
my $step1 = $interp1->step();
ok(!$step1->{done}, "First step not done");
ok($step1->{node_id} eq $start1->id || $step1->{node_id} eq $const1->id || $step1->{node_id} eq $const2->id,
   "First step is Start or a constant node");
ok($step1->{node_op} eq 'Start' || $step1->{node_op} eq 'Constant', "First step is Start or Constant operation");
ok($step1->{value} == 1 || $step1->{value} == 5 || $step1->{value} == 3, "First step value is 1 (Start), 5, or 3");

# Second step
my $step2 = $interp1->step();
ok(!$step2->{done}, "Second step not done");
ok($step2->{node_id} eq $start1->id || $step2->{node_id} eq $const1->id || $step2->{node_id} eq $const2->id,
   "Second step is Start or a constant node");

# Test 9-11: Third step completes the Start/constants, fourth step is Add
my $step3 = $interp1->step();
ok(!$step3->{done}, "Third step not done");
ok($step3->{node_id} eq $start1->id || $step3->{node_id} eq $const1->id || $step3->{node_id} eq $const2->id,
   "Third step is Start or a constant node");

my $step4 = $interp1->step();
ok(!$step4->{done}, "Fourth step not done");
is($step4->{node_id}, $add->id, "Fourth step is Add node");
is($step4->{value}, 8, "Add node computes 5 + 3 = 8");

# Test 12-14: Return node completes execution
my $step5 = $interp1->step();
ok($step5->{done}, "Fifth step is done (Return node)");
is($step5->{node_id}, $ret->id, "Fifth step is Return node");
is($step5->{value}, 8, "Return node returns 8");

# Test 15: Execution is complete
ok($interp1->is_stepping_complete(), "Stepping complete after Return");

# Test 16-17: Step when complete returns done status
my $step6 = $interp1->step();
ok($step6->{done}, "Step when complete returns done");
is($step6->{value}, 8, "Final value is 8");

# Test 18-19: State inspection during execution
my $graph2 = Chalk::IR::Graph->new();
my $start2 = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
my $c1 = Chalk::IR::Node::Constant->new(value => 10, type => Chalk::IR::Type::Integer->TOP());
my $c2 = Chalk::IR::Node::Constant->new(value => 20, type => Chalk::IR::Type::Integer->TOP());
my $add2 = Chalk::IR::Node::Add->new(left => $c1, right => $c2);
my $ret2 = Chalk::IR::Node::Return->new(
    control => $start2,
    value => $add2,
);

$graph2->add_node($start2);
$graph2->add_node($c1);
$graph2->add_node($c2);
$graph2->add_node($add2);
$graph2->add_node($ret2);

my $interp2 = Chalk::Interpreter::CEKDataflow->new(graph => $graph2);
$interp2->initialize_stepping();

$interp2->step();  # Execute first constant
my $mid_state = $interp2->get_step_state();
is(scalar(keys %{$mid_state->{computed}}), 1, "One node computed after first step");
ok(exists $mid_state->{waiting}->{$add2->id} || exists $mid_state->{waiting}->{$ret2->id},
   "Some nodes still waiting");

# Test 20-22: Step-by-step produces same result as execute()
my $graph3 = Chalk::IR::Graph->new();
my $start3 = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
my $c3 = Chalk::IR::Node::Constant->new(value => 15, type => Chalk::IR::Type::Integer->TOP());
my $c4 = Chalk::IR::Node::Constant->new(value => 25, type => Chalk::IR::Type::Integer->TOP());
my $add3 = Chalk::IR::Node::Add->new(left => $c3, right => $c4);
my $ret3 = Chalk::IR::Node::Return->new(
    control => $start3,
    value => $add3,
);

$graph3->add_node($start3);
$graph3->add_node($c3);
$graph3->add_node($c4);
$graph3->add_node($add3);
$graph3->add_node($ret3);

# Execute with full execute() method
my $interp3a = Chalk::Interpreter::CEKDataflow->new(graph => $graph3);
my $full_result = $interp3a->execute();

# Execute with step-by-step
my $interp3b = Chalk::Interpreter::CEKDataflow->new(graph => $graph3);
$interp3b->initialize_stepping();

my $step_result;
while (!$interp3b->is_stepping_complete()) {
    my $step = $interp3b->step();
    if ($step->{done}) {
        $step_result = $step->{value};
        last;
    }
}

is($full_result, 40, "Full execute() returns 40");
is($step_result, 40, "Step-by-step returns 40");
is($full_result, $step_result, "Both methods produce same result");

