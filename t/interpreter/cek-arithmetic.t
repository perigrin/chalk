#!/usr/bin/env perl
# ABOUTME: Test CEK interpreter execution with arithmetic operations
# ABOUTME: Tests Phase 1 success criterion: (1 + 2) * 3 = 9
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More;
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
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $const = Chalk::IR::Node::Constant->new(value => 42, type => 'int');
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $const,
    );

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
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c1 = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(value => 2, type => 'int');
    my $add = Chalk::IR::Node::Add->new(left => $c1, right => $c2);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $add,
    );

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
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c2 = Chalk::IR::Node::Constant->new(value => 2, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(value => 3, type => 'int');
    my $mul = Chalk::IR::Node::Multiply->new(left => $c2, right => $c3);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $mul,
    );

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
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c1 = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(value => 2, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(value => 3, type => 'int');
    my $add = Chalk::IR::Node::Add->new(left => $c1, right => $c2);
    my $mul = Chalk::IR::Node::Multiply->new(left => $add, right => $c3);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $mul,
    );

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
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c10 = Chalk::IR::Node::Constant->new(value => 10, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(value => 3, type => 'int');

    require Chalk::IR::Node::Subtract;
    my $sub = Chalk::IR::Node::Subtract->new(left => $c10, right => $c3);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $sub,
    );

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
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c20 = Chalk::IR::Node::Constant->new(value => 20, type => 'int');
    my $c4 = Chalk::IR::Node::Constant->new(value => 4, type => 'int');

    require Chalk::IR::Node::Divide;
    my $div = Chalk::IR::Node::Divide->new(left => $c20, right => $c4);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $div,
    );

    $graph->add_node($start);
    $graph->add_node($c20);
    $graph->add_node($c4);
    $graph->add_node($div);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 5, 'executes 20 / 4 = 5');
}

# Test negative numbers: -5 + 3 = -2
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c_neg5 = Chalk::IR::Node::Constant->new(value => -5, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(value => 3, type => 'int');
    my $add = Chalk::IR::Node::Add->new(left => $c_neg5, right => $c3);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $add,
    );

    $graph->add_node($start);
    $graph->add_node($c_neg5);
    $graph->add_node($c3);
    $graph->add_node($add);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, -2, 'executes negative: -5 + 3 = -2');
}

# Test zero in addition: 0 + 5 = 5
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c0 = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    my $c5 = Chalk::IR::Node::Constant->new(value => 5, type => 'int');
    my $add = Chalk::IR::Node::Add->new(left => $c0, right => $c5);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $add,
    );

    $graph->add_node($start);
    $graph->add_node($c0);
    $graph->add_node($c5);
    $graph->add_node($add);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 5, 'executes zero add: 0 + 5 = 5');
}

# Test zero in multiplication: 0 * 10 = 0
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c0 = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    my $c10 = Chalk::IR::Node::Constant->new(value => 10, type => 'int');
    my $mul = Chalk::IR::Node::Multiply->new(left => $c0, right => $c10);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $mul,
    );

    $graph->add_node($start);
    $graph->add_node($c0);
    $graph->add_node($c10);
    $graph->add_node($mul);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 0, 'executes zero multiply: 0 * 10 = 0');
}

# Test negative multiplication: -2 * 3 = -6
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c_neg2 = Chalk::IR::Node::Constant->new(value => -2, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(value => 3, type => 'int');
    my $mul = Chalk::IR::Node::Multiply->new(left => $c_neg2, right => $c3);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $mul,
    );

    $graph->add_node($start);
    $graph->add_node($c_neg2);
    $graph->add_node($c3);
    $graph->add_node($mul);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, -6, 'executes negative multiply: -2 * 3 = -6');
}

# Test division by zero (should fail gracefully)
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c10 = Chalk::IR::Node::Constant->new(value => 10, type => 'int');
    my $c0 = Chalk::IR::Node::Constant->new(value => 0, type => 'int');

    require Chalk::IR::Node::Divide;
    my $div = Chalk::IR::Node::Divide->new(left => $c10, right => $c0);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $div,
    );

    $graph->add_node($start);
    $graph->add_node($c10);
    $graph->add_node($c0);
    $graph->add_node($div);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);

    # Division by zero should either die or return undef/inf depending on implementation
    eval {
        my $result = $interp->execute();
        # If it returns a value, check for inf or undef
        ok(!defined($result) || $result eq 'inf' || $result eq 'Inf', 'division by zero handled: 10 / 0');
    };
    if ($@) {
        like($@, qr/division by zero|illegal division/i, 'division by zero throws error');
    }
}

# Test deeper expression tree: ((2 + 3) * 4) - 10 = 10
{
    my $graph = Chalk::IR::Graph->new();
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
    my $c2 = Chalk::IR::Node::Constant->new(value => 2, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(value => 3, type => 'int');
    my $c4 = Chalk::IR::Node::Constant->new(value => 4, type => 'int');
    my $c10 = Chalk::IR::Node::Constant->new(value => 10, type => 'int');

    my $add = Chalk::IR::Node::Add->new(left => $c2, right => $c3);
    my $mul = Chalk::IR::Node::Multiply->new(left => $add, right => $c4);

    require Chalk::IR::Node::Subtract;
    my $sub = Chalk::IR::Node::Subtract->new(left => $mul, right => $c10);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $sub,
    );

    $graph->add_node($start);
    $graph->add_node($c2);
    $graph->add_node($c3);
    $graph->add_node($c4);
    $graph->add_node($c10);
    $graph->add_node($add);
    $graph->add_node($mul);
    $graph->add_node($sub);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();
    is($result, 10, 'executes deep tree: ((2 + 3) * 4) - 10 = 10');
}

done_testing();
