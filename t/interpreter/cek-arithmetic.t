#!/usr/bin/env perl
# ABOUTME: Test CEK interpreter execution with arithmetic operations
# ABOUTME: Tests Phase 1 success criterion: (1 + 2) * 3 = 9
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 6;
use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Return;
use Chalk::Interpreter::CEKDataflow;

# Test simple constant execution
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $const = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 42, type => 'int');
    my $ret = Chalk::IR::Node::Return->new(id => 'node_2', inputs => ['node_0', 'node_1'], value_id => 'node_1', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($const);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 42, 'executes constant: 42');
}

# Test simple addition: 1 + 2 = 3
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $c1 = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 1, type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 2, type => 'int');
    my $add = Chalk::IR::Node::Add->new(id => 'node_3', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');
    my $ret = Chalk::IR::Node::Return->new(id => 'node_4', inputs => ['node_0', 'node_3'], value_id => 'node_3', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($add);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 3, 'executes 1 + 2 = 3');
}

# Test multiplication: 2 * 3 = 6
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $c2 = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 2, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 3, type => 'int');
    my $mul = Chalk::IR::Node::Multiply->new(id => 'node_3', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');
    my $ret = Chalk::IR::Node::Return->new(id => 'node_4', inputs => ['node_0', 'node_3'], value_id => 'node_3', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($c2);
    $graph->add_node($c3);
    $graph->add_node($mul);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 6, 'executes 2 * 3 = 6');
}

# Test Phase 1 success criterion: (1 + 2) * 3 = 9
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $c1 = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 1, type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 2, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(id => 'node_3', inputs => [], value => 3, type => 'int');
    my $add = Chalk::IR::Node::Add->new(id => 'node_4', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');
    my $mul = Chalk::IR::Node::Multiply->new(id => 'node_5', inputs => ['node_4', 'node_3'], left_id => 'node_4', right_id => 'node_3');
    my $ret = Chalk::IR::Node::Return->new(id => 'node_6', inputs => ['node_0', 'node_5'], value_id => 'node_5', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($c3);
    $graph->add_node($add);
    $graph->add_node($mul);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 9, 'Phase 1 success: (1 + 2) * 3 = 9');
}

# Test subtraction: 10 - 3 = 7
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $c10 = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 10, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 3, type => 'int');

    # Need to load Subtract
    require Chalk::IR::Node::Subtract;
    my $sub = Chalk::IR::Node::Subtract->new(id => 'node_3', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');
    my $ret = Chalk::IR::Node::Return->new(id => 'node_4', inputs => ['node_0', 'node_3'], value_id => 'node_3', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($c10);
    $graph->add_node($c3);
    $graph->add_node($sub);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 7, 'executes 10 - 3 = 7');
}

# Test division: 20 / 4 = 5
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $c20 = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 20, type => 'int');
    my $c4 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 4, type => 'int');

    # Need to load Divide
    require Chalk::IR::Node::Divide;
    my $div = Chalk::IR::Node::Divide->new(id => 'node_3', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');
    my $ret = Chalk::IR::Node::Return->new(id => 'node_4', inputs => ['node_0', 'node_3'], value_id => 'node_3', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($c20);
    $graph->add_node($c4);
    $graph->add_node($div);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 5, 'executes 20 / 4 = 5');
}
