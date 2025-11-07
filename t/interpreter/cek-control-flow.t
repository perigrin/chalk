#!/usr/bin/env perl
# ABOUTME: Test CEK interpreter execution with control flow operations (If, Proj, Region)
# ABOUTME: Tests Phase 2 Tasks 1-2: If, Proj, and Region node execution
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 5;
use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::GT;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Return;
use Chalk::Interpreter::CEKDataflow;

# Test simple If node: if (true condition)
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $cond_true = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 1, type => 'int');
    my $if_node = Chalk::IR::Node::If->new(id => 'node_2', inputs => ['node_1'], condition_id => 'node_1');
    my $ret = Chalk::IR::Node::Return->new(id => 'node_3', inputs => ['node_0', 'node_2'], value_id => 'node_2', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($cond_true);
    $graph->add_node($if_node);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 1, 'If node with true condition returns 1');
}

# Test Proj node true branch: if (true) then activate index 1
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $cond_true = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 1, type => 'int');
    my $if_node = Chalk::IR::Node::If->new(id => 'node_2', inputs => ['node_1'], condition_id => 'node_1');
    my $proj_true = Chalk::IR::Node::Proj->new(id => 'node_3', inputs => ['node_2'], index => 1, label => 'IfTrue');
    my $ret = Chalk::IR::Node::Return->new(id => 'node_4', inputs => ['node_0', 'node_3'], value_id => 'node_3', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($cond_true);
    $graph->add_node($if_node);
    $graph->add_node($proj_true);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 1, 'Proj node (index 1) with true condition returns 1');
}

# Test If with GT comparison: if (5 > 3) returns 1
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $c5 = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 5, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 3, type => 'int');
    my $gt = Chalk::IR::Node::GT->new(id => 'node_3', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');
    my $if_node = Chalk::IR::Node::If->new(id => 'node_4', inputs => ['node_3'], condition_id => 'node_3');
    my $ret = Chalk::IR::Node::Return->new(id => 'node_5', inputs => ['node_0', 'node_4'], value_id => 'node_4', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($c5);
    $graph->add_node($c3);
    $graph->add_node($gt);
    $graph->add_node($if_node);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 1, 'If node with GT comparison (5 > 3) returns 1');
}

# Test Region node merging true branch (index 1)
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $cond_true = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 1, type => 'int');
    my $if_node = Chalk::IR::Node::If->new(id => 'node_2', inputs => ['node_1'], condition_id => 'node_1');
    my $proj_false = Chalk::IR::Node::Proj->new(id => 'node_3', inputs => ['node_2'], index => 0, label => 'IfFalse');
    my $proj_true = Chalk::IR::Node::Proj->new(id => 'node_4', inputs => ['node_2'], index => 1, label => 'IfTrue');
    my $region = Chalk::IR::Node::Region->new(id => 'node_5', inputs => ['node_3', 'node_4']);
    my $ret = Chalk::IR::Node::Return->new(id => 'node_6', inputs => ['node_0', 'node_5'], value_id => 'node_5', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($cond_true);
    $graph->add_node($if_node);
    $graph->add_node($proj_false);
    $graph->add_node($proj_true);
    $graph->add_node($region);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 1, 'Region node with true branch returns index 1');
}

# Test Region node merging false branch (index 0)
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $cond_false = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 0, type => 'int');
    my $if_node = Chalk::IR::Node::If->new(id => 'node_2', inputs => ['node_1'], condition_id => 'node_1');
    my $proj_false = Chalk::IR::Node::Proj->new(id => 'node_3', inputs => ['node_2'], index => 0, label => 'IfFalse');
    my $proj_true = Chalk::IR::Node::Proj->new(id => 'node_4', inputs => ['node_2'], index => 1, label => 'IfTrue');
    my $region = Chalk::IR::Node::Region->new(id => 'node_5', inputs => ['node_3', 'node_4']);
    my $ret = Chalk::IR::Node::Return->new(id => 'node_6', inputs => ['node_0', 'node_5'], value_id => 'node_5', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($cond_false);
    $graph->add_node($if_node);
    $graph->add_node($proj_false);
    $graph->add_node($proj_true);
    $graph->add_node($region);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 0, 'Region node with false branch returns index 0');
}
