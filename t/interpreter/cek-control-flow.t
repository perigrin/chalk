#!/usr/bin/env perl
# ABOUTME: Test CEK interpreter execution with control flow operations (If, Proj, Region, Phi)
# ABOUTME: Tests Phase 2 Tasks 1-5: Complete if/else control flow with value selection
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 13;
use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::GT;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Return;
use Chalk::IR::Type::Integer;
use Chalk::Interpreter::CEKDataflow;

# Tests use content-addressable IDs computed from node contents
# Object references are used for graph traversal

# Test simple If node: if (true condition)
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $cond_true = Chalk::IR::Node::Constant->new(value => 1, type => Chalk::IR::Type::Integer->TOP());
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$cond_true->id],
        condition_id => $cond_true->id,
        condition => $cond_true,
    );
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $if_node,
    );

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
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $cond_true = Chalk::IR::Node::Constant->new(value => 1, type => Chalk::IR::Type::Integer->TOP());
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$cond_true->id],
        condition_id => $cond_true->id,
        condition => $cond_true,
    );
    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $proj_true,
    );

    $graph->add_node($start);
    $graph->add_node($cond_true);
    $graph->add_node($if_node);
    $graph->add_node($proj_true);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 1, 'Proj node (index 0) with true condition returns 1');
}

# Test If with GT comparison: if (5 > 3) returns 1
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c5 = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->TOP());
    my $c3 = Chalk::IR::Node::Constant->new(value => 3, type => Chalk::IR::Type::Integer->TOP());
    my $gt = Chalk::IR::Node::GT->new(
        left => $c5,
        right => $c3,
    );
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$gt->id],
        condition_id => $gt->id,
        condition => $gt,
    );
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $if_node,
    );

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

# Test Region node merging when true branch is active
# Region always returns 1 (control flows here), regardless of which branch is active
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $cond_true = Chalk::IR::Node::Constant->new(value => 1, type => Chalk::IR::Type::Integer->TOP());
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$cond_true->id],
        condition_id => $cond_true->id,
        condition => $cond_true,
    );
    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$proj_false->id, $proj_true->id],
    );
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $region,
    );

    $graph->add_node($start);
    $graph->add_node($cond_true);
    $graph->add_node($if_node);
    $graph->add_node($proj_false);
    $graph->add_node($proj_true);
    $graph->add_node($region);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 1, 'Region node returns 1 (control flows here) when true branch is active');
}

# Test Region node merging when false branch is active
# Region always returns 1 (control flows here), regardless of which branch is active
# The active path is tracked by Proj nodes, not by Region's return value
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $cond_false = Chalk::IR::Node::Constant->new(value => 0, type => Chalk::IR::Type::Integer->TOP());
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$cond_false->id],
        condition_id => $cond_false->id,
        condition => $cond_false,
    );
    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$proj_false->id, $proj_true->id],
    );
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $region,
    );

    $graph->add_node($start);
    $graph->add_node($cond_false);
    $graph->add_node($if_node);
    $graph->add_node($proj_false);
    $graph->add_node($proj_true);
    $graph->add_node($region);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 1, 'Region node returns 1 (control flows here) even when false branch is active');
}

# Test Phi node selecting true branch value
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $cond_true = Chalk::IR::Node::Constant->new(value => 1, type => Chalk::IR::Type::Integer->TOP());
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$cond_true->id],
        condition_id => $cond_true->id,
        condition => $cond_true,
    );
    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$proj_false->id, $proj_true->id],
    );
    my $val_false = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->TOP());
    my $val_true = Chalk::IR::Node::Constant->new(value => 99, type => Chalk::IR::Type::Integer->TOP());
    my $phi = Chalk::IR::Node::Phi->new(
        inputs => [$region->id, $val_false->id, $val_true->id],
        region_id => $region->id,
    );
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $phi,
    );

    $graph->add_node($start);
    $graph->add_node($cond_true);
    $graph->add_node($if_node);
    $graph->add_node($proj_false);
    $graph->add_node($proj_true);
    $graph->add_node($region);
    $graph->add_node($val_false);
    $graph->add_node($val_true);
    $graph->add_node($phi);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 99, 'Phi node selects true branch value (99)');
}

# Test Phi node selecting false branch value
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $cond_false = Chalk::IR::Node::Constant->new(value => 0, type => Chalk::IR::Type::Integer->TOP());
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$cond_false->id],
        condition_id => $cond_false->id,
        condition => $cond_false,
    );
    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$proj_false->id, $proj_true->id],
    );
    my $val_false = Chalk::IR::Node::Constant->new(value => 42, type => Chalk::IR::Type::Integer->TOP());
    my $val_true = Chalk::IR::Node::Constant->new(value => 99, type => Chalk::IR::Type::Integer->TOP());
    my $phi = Chalk::IR::Node::Phi->new(
        inputs => [$region->id, $val_false->id, $val_true->id],
        region_id => $region->id,
    );
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $phi,
    );

    $graph->add_node($start);
    $graph->add_node($cond_false);
    $graph->add_node($if_node);
    $graph->add_node($proj_false);
    $graph->add_node($proj_true);
    $graph->add_node($region);
    $graph->add_node($val_false);
    $graph->add_node($val_true);
    $graph->add_node($phi);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 42, 'Phi node selects false branch value (42)');
}

# Test complete if/else pattern: max(x, y) where x > y
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $x = Chalk::IR::Node::Constant->new(value => 10, type => Chalk::IR::Type::Integer->TOP());
    my $y = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->TOP());
    my $gt = Chalk::IR::Node::GT->new(
        left => $x,
        right => $y,
    );
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$gt->id],
        condition_id => $gt->id,
        condition => $gt,
    );
    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$proj_false->id, $proj_true->id],
    );
    my $phi = Chalk::IR::Node::Phi->new(
        inputs => [$region->id, $y->id, $x->id],
        region_id => $region->id,
    );
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $phi,
    );

    $graph->add_node($start);
    $graph->add_node($x);
    $graph->add_node($y);
    $graph->add_node($gt);
    $graph->add_node($if_node);
    $graph->add_node($proj_false);
    $graph->add_node($proj_true);
    $graph->add_node($region);
    $graph->add_node($phi);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 10, 'If/else pattern: max(10, 5) returns 10');
}

# Test complete if/else pattern: max(x, y) where x < y
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $x = Chalk::IR::Node::Constant->new(value => 3, type => Chalk::IR::Type::Integer->TOP());
    my $y = Chalk::IR::Node::Constant->new(value => 8, type => Chalk::IR::Type::Integer->TOP());
    my $gt = Chalk::IR::Node::GT->new(
        left => $x,
        right => $y,
    );
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$gt->id],
        condition_id => $gt->id,
        condition => $gt,
    );
    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$proj_false->id, $proj_true->id],
    );
    my $phi = Chalk::IR::Node::Phi->new(
        inputs => [$region->id, $y->id, $x->id],
        region_id => $region->id,
    );
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $phi,
    );

    $graph->add_node($start);
    $graph->add_node($x);
    $graph->add_node($y);
    $graph->add_node($gt);
    $graph->add_node($if_node);
    $graph->add_node($proj_false);
    $graph->add_node($proj_true);
    $graph->add_node($region);
    $graph->add_node($phi);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 8, 'If/else pattern: max(3, 8) returns 8');
}

# Test if/else with arithmetic in true branch: if (x > 5) then x+100 else 200
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $x = Chalk::IR::Node::Constant->new(value => 7, type => Chalk::IR::Type::Integer->TOP());
    my $five = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->TOP());
    my $hundred = Chalk::IR::Node::Constant->new(value => 100, type => Chalk::IR::Type::Integer->TOP());
    my $two_hundred = Chalk::IR::Node::Constant->new(value => 200, type => Chalk::IR::Type::Integer->TOP());
    my $gt = Chalk::IR::Node::GT->new(
        left => $x,
        right => $five,
    );
    my $if_node = Chalk::IR::Node::If->new(
        inputs => [$gt->id],
        condition_id => $gt->id,
        condition => $gt,
    );
    my $proj_false = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 1,
        label => 'IfFalse',
        source => $if_node,
    );
    my $proj_true = Chalk::IR::Node::Proj->new(
        inputs => [$if_node->id],
        index => 0,
        label => 'IfTrue',
        source => $if_node,
    );
    my $add = Chalk::IR::Node::Add->new(left => $x, right => $hundred);
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$proj_false->id, $proj_true->id],
    );
    my $phi = Chalk::IR::Node::Phi->new(
        inputs => [$region->id, $two_hundred->id, $add->id],
        region_id => $region->id,
    );
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $phi,
    );

    $graph->add_node($start);
    $graph->add_node($x);
    $graph->add_node($five);
    $graph->add_node($hundred);
    $graph->add_node($two_hundred);
    $graph->add_node($gt);
    $graph->add_node($if_node);
    $graph->add_node($proj_false);
    $graph->add_node($proj_true);
    $graph->add_node($add);
    $graph->add_node($region);
    $graph->add_node($phi);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 107, 'If/else with computation: (7 > 5) ? 7+100 : 200 returns 107');
}

# Test Region node validation: reject invalid Proj return value
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    # Create a constant that will be used as a fake Proj result (invalid value)
    my $invalid = Chalk::IR::Node::Constant->new(value => 2, type => Chalk::IR::Type::Integer->TOP());
    my $region = Chalk::IR::Node::Region->new(
        inputs => [$invalid->id],
    );
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $region,
    );

    $graph->add_node($start);
    $graph->add_node($invalid);
    $graph->add_node($region);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    eval { $interp->execute(); };
    like($@, qr/Region node.*returned invalid value: 2/, 'Region rejects Proj returning invalid value (2)');
}

# Test Region node validation: reject multiple active paths
# We need to create a custom mock graph for this since normal If/Proj can't create this state
{
    # This test requires manually constructing an invalid IR graph where two Proj nodes return 1
    # We'll use a custom context that simulates this invalid state
use Chalk::IR::Type::Integer;
    use Chalk::Interpreter::CEKDataflow;

    my $region = Chalk::IR::Node::Region->new(inputs => ['proj_0', 'proj_1']);

    # Create a mock context that returns 1 for both proj nodes
    my $mock_context = sub {
        my ($key) = @_;
        return 1 if $key eq 'node:proj_0';
        return 1 if $key eq 'node:proj_1';
        return 0;
    };

    eval { $region->execute($mock_context); };
    like($@, qr/Region node.*multiple active paths/, 'Region rejects multiple active paths');
}

# Test Region node validation: reject no active paths (all Proj return 0)
{
    my $region = Chalk::IR::Node::Region->new(inputs => ['proj_0', 'proj_1']);

    # Create a mock context that returns 0 for both proj nodes
    my $mock_context = sub {
        my ($key) = @_;
        return 0 if $key eq 'node:proj_0';
        return 0 if $key eq 'node:proj_1';
        return 0;
    };

    eval { $region->execute($mock_context); };
    like($@, qr/Region node.*no active input path/, 'Region rejects no active paths');
}
