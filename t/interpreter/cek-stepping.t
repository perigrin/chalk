use 5.42.0;
use Test::More tests => 22;
use Chalk::IR::Graph;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Return;
use Chalk::Interpreter::CEKDataflow;

# Test 1-2: Basic stepping initialization
my $graph1 = Chalk::IR::Graph->new();
my $const1 = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 5, type => 'int');
my $const2 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 3, type => 'int');
my $add = Chalk::IR::Node::Add->new(id => 'node_3', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');
my $ret = Chalk::IR::Node::Return->new(id => 'node_4', inputs => ['node_3'], value_id => 'node_3', control_id => 'node_3');

$graph1->add_node($const1);
$graph1->add_node($const2);
$graph1->add_node($add);
$graph1->add_node($ret);

my $interp1 = Chalk::Interpreter::CEKDataflow->new(graph => $graph1);
$interp1->initialize_stepping();

ok(!$interp1->is_stepping_complete(), "Stepping not complete after initialization");

my $state1 = $interp1->get_step_state();
is(scalar(@{$state1->{ready_queue}}), 2, "Two nodes ready initially (both constants)");

# Test 3-8: Step through execution
my $step1 = $interp1->step();
ok(!$step1->{done}, "First step not done");
ok($step1->{node_id} eq 'node_1' || $step1->{node_id} eq 'node_2', "First step is a constant node");
is($step1->{node_op}, 'Constant', "First step is Constant operation");
ok($step1->{value} == 5 || $step1->{value} == 3, "First step value is 5 or 3");

my $step2 = $interp1->step();
ok(!$step2->{done}, "Second step not done");
ok($step2->{node_id} eq 'node_1' || $step2->{node_id} eq 'node_2', "Second step is a constant node");

# Test 9-11: Add node becomes ready
my $step3 = $interp1->step();
ok(!$step3->{done}, "Third step not done");
is($step3->{node_id}, 'node_3', "Third step is Add node");
is($step3->{value}, 8, "Add node computes 5 + 3 = 8");

# Test 12-14: Return node completes execution
my $step4 = $interp1->step();
ok($step4->{done}, "Fourth step is done (Return node)");
is($step4->{node_id}, 'node_4', "Fourth step is Return node");
is($step4->{value}, 8, "Return node returns 8");

# Test 15: Execution is complete
ok($interp1->is_stepping_complete(), "Stepping complete after Return");

# Test 16-17: Step when complete returns done status
my $step5 = $interp1->step();
ok($step5->{done}, "Step when complete returns done");
is($step5->{value}, 8, "Final value is 8");

# Test 18-19: State inspection during execution
my $graph2 = Chalk::IR::Graph->new();
my $c1 = Chalk::IR::Node::Constant->new(id => 'n1', inputs => [], value => 10, type => 'int');
my $c2 = Chalk::IR::Node::Constant->new(id => 'n2', inputs => [], value => 20, type => 'int');
my $add2 = Chalk::IR::Node::Add->new(id => 'n3', inputs => ['n1', 'n2'], left_id => 'n1', right_id => 'n2');
my $ret2 = Chalk::IR::Node::Return->new(id => 'n4', inputs => ['n3'], value_id => 'n3', control_id => 'n3');

$graph2->add_node($c1);
$graph2->add_node($c2);
$graph2->add_node($add2);
$graph2->add_node($ret2);

my $interp2 = Chalk::Interpreter::CEKDataflow->new(graph => $graph2);
$interp2->initialize_stepping();

$interp2->step();  # Execute first constant
my $mid_state = $interp2->get_step_state();
is(scalar(keys %{$mid_state->{computed}}), 1, "One node computed after first step");
ok(exists $mid_state->{waiting}->{'n3'} || exists $mid_state->{waiting}->{'n4'},
   "Some nodes still waiting");

# Test 20-22: Step-by-step produces same result as execute()
my $graph3 = Chalk::IR::Graph->new();
my $c3 = Chalk::IR::Node::Constant->new(id => 'x1', inputs => [], value => 15, type => 'int');
my $c4 = Chalk::IR::Node::Constant->new(id => 'x2', inputs => [], value => 25, type => 'int');
my $add3 = Chalk::IR::Node::Add->new(id => 'x3', inputs => ['x1', 'x2'], left_id => 'x1', right_id => 'x2');
my $ret3 = Chalk::IR::Node::Return->new(id => 'x4', inputs => ['x3'], value_id => 'x3', control_id => 'x3');

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

