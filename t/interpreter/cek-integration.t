#!/usr/bin/env perl
# ABOUTME: Integration tests for CEK interpreter combining arithmetic, arrays, hashes, and stepping modes
# ABOUTME: Verifies complex expressions work correctly and that execute() and step() modes produce identical results
use 5.42.0;
use Test::More tests => 8;
use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::GT;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::NewArray;
use Chalk::IR::Node::ArrayStore;
use Chalk::IR::Node::ArrayLoad;
use Chalk::IR::Node::NewHash;
use Chalk::IR::Node::HashStore;
use Chalk::IR::Node::HashLoad;
use Chalk::Interpreter::CEKDataflow;
use Chalk::Interpreter::ExecutionLog;

# Test 1-2: Complex arithmetic expression: (10 + 5) * (8 - 3)
{
    my $graph = Chalk::IR::Graph->new();

    my $c1 = Chalk::IR::Node::Constant->new(id => 'c1', inputs => [], value => 10, type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(id => 'c2', inputs => [], value => 5, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(id => 'c3', inputs => [], value => 8, type => 'int');
    my $c4 = Chalk::IR::Node::Constant->new(id => 'c4', inputs => [], value => 3, type => 'int');

    my $add = Chalk::IR::Node::Add->new(id => 'add', inputs => ['c1', 'c2'],
        left_id => 'c1', right_id => 'c2');
    my $sub = Chalk::IR::Node::Subtract->new(id => 'sub', inputs => ['c3', 'c4'],
        left_id => 'c3', right_id => 'c4');
    my $mul = Chalk::IR::Node::Multiply->new(id => 'mul', inputs => ['add', 'sub'],
        left_id => 'add', right_id => 'sub');
    my $ret = Chalk::IR::Node::Return->new(id => 'ret', inputs => ['mul'],
        value_id => 'mul', control_id => 'mul');

    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($c3);
    $graph->add_node($c4);
    $graph->add_node($add);
    $graph->add_node($sub);
    $graph->add_node($mul);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();

    is($result, 75, "Complex arithmetic: (10 + 5) * (8 - 3) = 75");

    # Test with stepping mode
    my $interp2 = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    $interp2->initialize_stepping();

    my $step_result;
    while (!$interp2->is_stepping_complete()) {
        my $step = $interp2->step();
        if ($step->{done}) {
            $step_result = $step->{value};
            last;
        }
    }

    is($step_result, 75, "Stepping mode produces same result");
}

# Test 3-5: Array operations
{
    my $graph = Chalk::IR::Graph->new();

    my $arr = Chalk::IR::Node::NewArray->new(id => 'arr', inputs => []);
    my $c1 = Chalk::IR::Node::Constant->new(id => 'c1', inputs => [], value => 10, type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(id => 'c2', inputs => [], value => 5, type => 'int');
    my $sum = Chalk::IR::Node::Add->new(id => 'sum', inputs => ['c1', 'c2'],
        left_id => 'c1', right_id => 'c2');

    my $idx0 = Chalk::IR::Node::Constant->new(id => 'idx0', inputs => [], value => 0, type => 'int');
    my $store1 = Chalk::IR::Node::ArrayStore->new(id => 'store1', inputs => ['arr', 'idx0', 'sum'],
        array_id => 'arr', index_id => 'idx0', value_id => 'sum');

    my $product = Chalk::IR::Node::Multiply->new(id => 'product', inputs => ['c1', 'c2'],
        left_id => 'c1', right_id => 'c2');

    my $idx1 = Chalk::IR::Node::Constant->new(id => 'idx1', inputs => [], value => 1, type => 'int');
    my $store2 = Chalk::IR::Node::ArrayStore->new(id => 'store2', inputs => ['store1', 'idx1', 'product'],
        array_id => 'store1', index_id => 'idx1', value_id => 'product');

    my $load0 = Chalk::IR::Node::ArrayLoad->new(id => 'load0', inputs => ['store2', 'idx0'],
        array_id => 'store2', index_id => 'idx0');
    my $load1 = Chalk::IR::Node::ArrayLoad->new(id => 'load1', inputs => ['store2', 'idx1'],
        array_id => 'store2', index_id => 'idx1');

    my $result_sum = Chalk::IR::Node::Add->new(id => 'result_sum', inputs => ['load0', 'load1'],
        left_id => 'load0', right_id => 'load1');

    my $ret = Chalk::IR::Node::Return->new(id => 'ret', inputs => ['result_sum'],
        value_id => 'result_sum', control_id => 'result_sum');

    $graph->add_node($arr);
    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($sum);
    $graph->add_node($idx0);
    $graph->add_node($store1);
    $graph->add_node($product);
    $graph->add_node($idx1);
    $graph->add_node($store2);
    $graph->add_node($load0);
    $graph->add_node($load1);
    $graph->add_node($result_sum);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();

    is($result, 65, "Array operations: (10+5) + (10*5) = 65");

    # Test stepping
    my $interp2 = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    $interp2->initialize_stepping();

    my $step_count = 0;
    while (!$interp2->is_stepping_complete()) {
        my $step = $interp2->step();
        $step_count++;
        last if $step->{done};
    }

    ok($step_count > 5, "Array operations take multiple steps");

    # Test logging
    my $log = Chalk::Interpreter::ExecutionLog->new(graph => $graph);
    my $interp3 = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    $interp3->initialize_stepping();

    my $step_num = 1;
    while (!$interp3->is_stepping_complete()) {
        my $step_report = $interp3->step();
        $log->add_step($step_num++, $step_report);
        last if $step_report->{done};
    }

    my $summary = $log->format_summary();
    like($summary, qr/NewArray|ArrayStore|ArrayLoad/, "Log shows array operations");
}

# Test 6-8: Hash operations
{
    my $graph = Chalk::IR::Graph->new();

    my $hash = Chalk::IR::Node::NewHash->new(id => 'hash', inputs => []);

    my $key1 = Chalk::IR::Node::Constant->new(id => 'key1', inputs => [], value => 'sum', type => 'string');
    my $c1 = Chalk::IR::Node::Constant->new(id => 'c1', inputs => [], value => 20, type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(id => 'c2', inputs => [], value => 15, type => 'int');
    my $sum = Chalk::IR::Node::Add->new(id => 'sum', inputs => ['c1', 'c2'],
        left_id => 'c1', right_id => 'c2');

    my $store1 = Chalk::IR::Node::HashStore->new(id => 'store1', inputs => ['hash', 'key1', 'sum'],
        hash_id => 'hash', key_id => 'key1', value_id => 'sum');

    my $key2 = Chalk::IR::Node::Constant->new(id => 'key2', inputs => [], value => 'diff', type => 'string');
    my $diff = Chalk::IR::Node::Subtract->new(id => 'diff', inputs => ['c1', 'c2'],
        left_id => 'c1', right_id => 'c2');

    my $store2 = Chalk::IR::Node::HashStore->new(id => 'store2', inputs => ['store1', 'key2', 'diff'],
        hash_id => 'store1', key_id => 'key2', value_id => 'diff');

    my $load1 = Chalk::IR::Node::HashLoad->new(id => 'load1', inputs => ['store2', 'key1'],
        hash_id => 'store2', key_id => 'key1');
    my $load2 = Chalk::IR::Node::HashLoad->new(id => 'load2', inputs => ['store2', 'key2'],
        hash_id => 'store2', key_id => 'key2');

    my $result_mul = Chalk::IR::Node::Multiply->new(id => 'result_mul', inputs => ['load1', 'load2'],
        left_id => 'load1', right_id => 'load2');

    my $ret = Chalk::IR::Node::Return->new(id => 'ret', inputs => ['result_mul'],
        value_id => 'result_mul', control_id => 'result_mul');

    $graph->add_node($hash);
    $graph->add_node($key1);
    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($sum);
    $graph->add_node($store1);
    $graph->add_node($key2);
    $graph->add_node($diff);
    $graph->add_node($store2);
    $graph->add_node($load1);
    $graph->add_node($load2);
    $graph->add_node($result_mul);
    $graph->add_node($ret);

    my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $result = $interp->execute();

    is($result, 175, "Hash operations: (20+15) * (20-15) = 175");

    # Test stepping
    my $interp2 = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    $interp2->initialize_stepping();

    my $step_result;
    while (!$interp2->is_stepping_complete()) {
        my $step = $interp2->step();
        if ($step->{done}) {
            $step_result = $step->{value};
            last;
        }
    }

    is($step_result, 175, "Stepping mode matches execute() for hash operations");

    # Test detailed logging
    my $log = Chalk::Interpreter::ExecutionLog->new(graph => $graph);
    my $interp3 = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    $interp3->initialize_stepping();

    my $step_num = 1;
    while (!$interp3->is_stepping_complete()) {
        my $step_report = $interp3->step();
        $log->add_step($step_num++, $step_report);
        last if $step_report->{done};
    }

    my $detailed = $log->format_detailed();
    like($detailed, qr/NewHash.*HashStore.*HashLoad/s, "Detailed log shows hash operation sequence");
}
