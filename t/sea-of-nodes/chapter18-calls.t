#!/usr/bin/env perl
# ABOUTME: Test Sea of Nodes Chapter 11 - Function Calls and Interprocedural
# ABOUTME: Validates Call nodes, function parameters, return values, and call graphs

use lib 'lib';
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use Chalk::IR::Node;
use Chalk::IR::Graph;

subtest 'Call node basic structure' => sub {
    # result = foo()
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    # Call: control, memory, function reference, arguments...
    my $call = Chalk::IR::Node->new(
        id => 2,
        op => 'Call',
        inputs => [$start->id, $start->id],
        attributes => { function => 'foo' },
    );
    $graph->add_node($call);

    is $call->op, 'Call', 'Call node created';
    is $call->attributes->{function}, 'foo', 'Call has function name';
    is scalar($call->inputs->@*), 2, 'Call has control and memory inputs';
};

subtest 'Call with arguments' => sub {
    # result = add(5, 3)
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $arg1 = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 5 },
    );
    $graph->add_node($arg1);

    my $arg2 = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 3 },
    );
    $graph->add_node($arg2);

    # Call: control, memory, arg1, arg2
    my $call = Chalk::IR::Node->new(
        id => 4,
        op => 'Call',
        inputs => [$start->id, $start->id, $arg1->id, $arg2->id],
        attributes => { function => 'add' },
    );
    $graph->add_node($call);

    is scalar($call->inputs->@*), 4, 'Call has control, memory, and 2 arguments';
    is $call->inputs->[2], $arg1->id, 'First argument connected';
    is $call->inputs->[3], $arg2->id, 'Second argument connected';
};

subtest 'Call with return value' => sub {
    # x = compute(); y = x + 1;
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    # Call returns a value
    my $call = Chalk::IR::Node->new(
        id => 2,
        op => 'Call',
        inputs => [$start->id, $start->id],
        attributes => { function => 'compute' },
    );
    $graph->add_node($call);

    # Projection to extract return value from call tuple
    # Call node returns: (control, memory, return_value)
    my $proj_return = Chalk::IR::Node->new(
        id => 3,
        op => 'Proj',
        inputs => [$call->id],
        attributes => { index => 2, label => 'return_value' },
    );
    $graph->add_node($proj_return);

    my $const_1 = Chalk::IR::Node->new(
        id => 4,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_1);

    my $add = Chalk::IR::Node->new(
        id => 5,
        op => 'Add',
        inputs => [$proj_return->id, $const_1->id],
        attributes => {},
    );
    $graph->add_node($add);

    is $proj_return->op, 'Proj', 'Projection extracts return value';
    is $proj_return->attributes->{label}, 'return_value', 'Projection labeled';
    is $add->inputs->[0], $proj_return->id, 'Add uses call return value';
};

subtest 'Call control and memory effects' => sub {
    # Calls produce control and memory effects
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $call = Chalk::IR::Node->new(
        id => 2,
        op => 'Call',
        inputs => [$start->id, $start->id],
        attributes => { function => 'foo' },
    );
    $graph->add_node($call);

    # Project control output
    my $proj_ctrl = Chalk::IR::Node->new(
        id => 3,
        op => 'Proj',
        inputs => [$call->id],
        attributes => { index => 0, label => 'control' },
    );
    $graph->add_node($proj_ctrl);

    # Project memory output
    my $proj_mem = Chalk::IR::Node->new(
        id => 4,
        op => 'Proj',
        inputs => [$call->id],
        attributes => { index => 1, label => 'memory' },
    );
    $graph->add_node($proj_mem);

    is $proj_ctrl->attributes->{label}, 'control', 'Control projection from call';
    is $proj_mem->attributes->{label}, 'memory', 'Memory projection from call';
};

subtest 'Sequential calls: chaining control and memory' => sub {
    # x = foo(); y = bar(); z = baz();
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    # First call
    my $call1 = Chalk::IR::Node->new(
        id => 2,
        op => 'Call',
        inputs => [$start->id, $start->id],
        attributes => { function => 'foo' },
    );
    $graph->add_node($call1);

    my $call1_ctrl = Chalk::IR::Node->new(
        id => 3,
        op => 'Proj',
        inputs => [$call1->id],
        attributes => { index => 0 },
    );
    $graph->add_node($call1_ctrl);

    my $call1_mem = Chalk::IR::Node->new(
        id => 4,
        op => 'Proj',
        inputs => [$call1->id],
        attributes => { index => 1 },
    );
    $graph->add_node($call1_mem);

    # Second call (uses control and memory from first)
    my $call2 = Chalk::IR::Node->new(
        id => 5,
        op => 'Call',
        inputs => [$call1_ctrl->id, $call1_mem->id],
        attributes => { function => 'bar' },
    );
    $graph->add_node($call2);

    my $call2_ctrl = Chalk::IR::Node->new(
        id => 6,
        op => 'Proj',
        inputs => [$call2->id],
        attributes => { index => 0 },
    );
    $graph->add_node($call2_ctrl);

    my $call2_mem = Chalk::IR::Node->new(
        id => 7,
        op => 'Proj',
        inputs => [$call2->id],
        attributes => { index => 1 },
    );
    $graph->add_node($call2_mem);

    # Third call (uses control and memory from second)
    my $call3 = Chalk::IR::Node->new(
        id => 8,
        op => 'Call',
        inputs => [$call2_ctrl->id, $call2_mem->id],
        attributes => { function => 'baz' },
    );
    $graph->add_node($call3);

    is $call2->inputs->[0], $call1_ctrl->id, 'Second call uses first call control';
    is $call2->inputs->[1], $call1_mem->id, 'Second call uses first call memory';
    is $call3->inputs->[0], $call2_ctrl->id, 'Third call uses second call control';
};

subtest 'Recursive call: factorial' => sub {
    # factorial(n) = if (n <= 1) return 1; else return n * factorial(n-1);
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => { function => 'factorial', params => ['n'] },
    );
    $graph->add_node($start);

    # Extract parameter n
    my $proj_n = Chalk::IR::Node->new(
        id => 2,
        op => 'Proj',
        inputs => [$start->id],
        attributes => { index => 0, label => 'param_n' },
    );
    $graph->add_node($proj_n);

    my $const_1 = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 1 },
    );
    $graph->add_node($const_1);

    # Check n <= 1
    my $le = Chalk::IR::Node->new(
        id => 4,
        op => 'LE',
        inputs => [$proj_n->id, $const_1->id],
        attributes => {},
    );
    $graph->add_node($le);

    my $if_node = Chalk::IR::Node->new(
        id => 5,
        op => 'If',
        inputs => [$start->id, $le->id],
        attributes => {},
    );
    $graph->add_node($if_node);

    # Base case: return 1
    # Recursive case: recursive call
    ok $start->attributes->{function}, 'Function has name';
    ok $proj_n, 'Parameter extracted';
    ok $if_node, 'Recursive function has conditional';
};

subtest 'Call in loop: function called repeatedly' => sub {
    # while (i < 10) { process(i); i++; }
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

    my $const_0 = Chalk::IR::Node->new(
        id => 3,
        op => 'Constant',
        inputs => [],
        attributes => { value => 0 },
    );
    $graph->add_node($const_0);

    my $phi_i = Chalk::IR::Node->new(
        id => 4,
        op => 'Phi',
        inputs => [$loop->id, $const_0->id],
        attributes => {},
    );
    $graph->add_node($phi_i);

    # Memory phi for effects across loop iterations
    my $phi_mem = Chalk::IR::Node->new(
        id => 5,
        op => 'Phi',
        inputs => [$loop->id, $start->id],
        attributes => { type => 'memory' },
    );
    $graph->add_node($phi_mem);

    # Call process(i)
    my $call = Chalk::IR::Node->new(
        id => 6,
        op => 'Call',
        inputs => [$loop->id, $phi_mem->id, $phi_i->id],
        attributes => { function => 'process' },
    );
    $graph->add_node($call);

    # Extract memory effect from call
    my $call_mem = Chalk::IR::Node->new(
        id => 7,
        op => 'Proj',
        inputs => [$call->id],
        attributes => { index => 1 },
    );
    $graph->add_node($call_mem);

    # Update memory phi with call's memory
    push $phi_mem->inputs->@*, $call_mem->id;

    is scalar($phi_mem->inputs->@*), 3, 'Memory phi has control, init, and loop value';
    is $call->inputs->[2], $phi_i->id, 'Call receives loop variable as argument';
};

subtest 'Multiple return values: tuple projection' => sub {
    # (x, y) = get_pair()
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $call = Chalk::IR::Node->new(
        id => 2,
        op => 'Call',
        inputs => [$start->id, $start->id],
        attributes => { function => 'get_pair' },
    );
    $graph->add_node($call);

    # Call returns tuple: (control, memory, value1, value2)
    # Project first return value
    my $proj_val1 = Chalk::IR::Node->new(
        id => 3,
        op => 'Proj',
        inputs => [$call->id],
        attributes => { index => 2, label => 'return_0' },
    );
    $graph->add_node($proj_val1);

    # Project second return value
    my $proj_val2 = Chalk::IR::Node->new(
        id => 4,
        op => 'Proj',
        inputs => [$call->id],
        attributes => { index => 3, label => 'return_1' },
    );
    $graph->add_node($proj_val2);

    is $proj_val1->attributes->{label}, 'return_0', 'First return value projected';
    is $proj_val2->attributes->{label}, 'return_1', 'Second return value projected';
    is $proj_val1->inputs->[0], $call->id, 'Both projections from same call';
    is $proj_val2->inputs->[0], $call->id, 'Both projections from same call';
};

subtest 'Function pointer / indirect call' => sub {
    # fn = get_function(); result = fn(arg);
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    # Get function pointer
    my $get_fn = Chalk::IR::Node->new(
        id => 2,
        op => 'Call',
        inputs => [$start->id, $start->id],
        attributes => { function => 'get_function' },
    );
    $graph->add_node($get_fn);

    my $fn_ptr = Chalk::IR::Node->new(
        id => 3,
        op => 'Proj',
        inputs => [$get_fn->id],
        attributes => { index => 2 },
    );
    $graph->add_node($fn_ptr);

    my $arg = Chalk::IR::Node->new(
        id => 4,
        op => 'Constant',
        inputs => [],
        attributes => { value => 42 },
    );
    $graph->add_node($arg);

    # Indirect call through function pointer
    my $indirect_call = Chalk::IR::Node->new(
        id => 5,
        op => 'Call',
        inputs => [$start->id, $start->id, $fn_ptr->id, $arg->id],
        attributes => { indirect => 1 },
    );
    $graph->add_node($indirect_call);

    is $indirect_call->attributes->{indirect}, 1, 'Call marked as indirect';
    is $indirect_call->inputs->[2], $fn_ptr->id, 'Call uses function pointer';
};

subtest 'Tail call optimization marker' => sub {
    # return foo(); (tail call)
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $call = Chalk::IR::Node->new(
        id => 2,
        op => 'Call',
        inputs => [$start->id, $start->id],
        attributes => { function => 'foo', tail_call => 1 },
    );
    $graph->add_node($call);

    my $proj_return = Chalk::IR::Node->new(
        id => 3,
        op => 'Proj',
        inputs => [$call->id],
        attributes => { index => 2 },
    );
    $graph->add_node($proj_return);

    my $return_node = Chalk::IR::Node->new(
        id => 4,
        op => 'Return',
        inputs => [$call->id, $proj_return->id],
        attributes => {},
    );
    $graph->add_node($return_node);

    is $call->attributes->{tail_call}, 1, 'Call marked as tail call';
    is $return_node->inputs->[1], $proj_return->id, 'Return uses call result directly';
};

subtest 'JSON serialization with Call nodes' => sub {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node->new(
        id => 1,
        op => 'Start',
        inputs => [],
        attributes => {},
    );
    $graph->add_node($start);

    my $arg = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => { value => 5 },
    );
    $graph->add_node($arg);

    my $call = Chalk::IR::Node->new(
        id => 3,
        op => 'Call',
        inputs => [$start->id, $start->id, $arg->id],
        attributes => { function => 'compute' },
    );
    $graph->add_node($call);

    my $json = $graph->to_json();

    my $has_call = scalar(grep { $_->{op} eq 'Call' } $json->{nodes}->@*);
    ok $has_call, 'Call node in JSON';

    my ($call_node) = grep { $_->{op} eq 'Call' } $json->{nodes}->@*;
    is $call_node->{attributes}{function}, 'compute', 'Function name in JSON';
};
