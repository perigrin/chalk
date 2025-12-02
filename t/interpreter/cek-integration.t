#!/usr/bin/env perl
# ABOUTME: Integration tests for CEK interpreter combining arithmetic, arrays, hashes, and stepping modes
# ABOUTME: Verifies complex expressions work correctly and that execute() and step() modes produce identical results
use 5.42.0;
use lib 'lib';
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
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);

    my $c1 = Chalk::IR::Node::Constant->new(value => 10, type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(value => 5, type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(value => 8, type => 'int');
    my $c4 = Chalk::IR::Node::Constant->new(value => 3, type => 'int');

    my $add = Chalk::IR::Node::Add->new(left => $c1, right => $c2);
    my $sub = Chalk::IR::Node::Subtract->new(left => $c3, right => $c4);
    my $mul = Chalk::IR::Node::Multiply->new(left => $add, right => $sub);
    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $mul,
    );

    $graph->add_node($start);
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
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);

    my $arr = Chalk::IR::Node::NewArray->new(
        inputs => [],
    );
    my $c1 = Chalk::IR::Node::Constant->new(value => 10, type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(value => 5, type => 'int');
    my $sum = Chalk::IR::Node::Add->new(left => $c1, right => $c2);

    my $idx0 = Chalk::IR::Node::Constant->new(value => 0, type => 'int');
    my $store1 = Chalk::IR::Node::ArrayStore->new(
        inputs => [$arr->id, $idx0->id, $sum->id],
        array_id => $arr->id,
        index_id => $idx0->id,
        value_id => $sum->id,
    );

    my $product = Chalk::IR::Node::Multiply->new(left => $c1, right => $c2);

    my $idx1 = Chalk::IR::Node::Constant->new(value => 1, type => 'int');
    my $store2 = Chalk::IR::Node::ArrayStore->new(
        inputs => [$store1->id, $idx1->id, $product->id],
        array_id => $store1->id,
        index_id => $idx1->id,
        value_id => $product->id,
    );

    my $load0 = Chalk::IR::Node::ArrayLoad->new(
        inputs => [$store2->id, $idx0->id],
        array_id => $store2->id,
        index_id => $idx0->id,
    );
    my $load1 = Chalk::IR::Node::ArrayLoad->new(
        inputs => [$store2->id, $idx1->id],
        array_id => $store2->id,
        index_id => $idx1->id,
    );

    my $result_sum = Chalk::IR::Node::Add->new(left => $load0, right => $load1);

    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $result_sum,
    );

    $graph->add_node($start);
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
    my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);

    my $hash = Chalk::IR::Node::NewHash->new(
        inputs => [],
    );

    my $key1 = Chalk::IR::Node::Constant->new(value => 'sum', type => 'string');
    my $c1 = Chalk::IR::Node::Constant->new(value => 20, type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(value => 15, type => 'int');
    my $sum = Chalk::IR::Node::Add->new(left => $c1, right => $c2);

    my $store1 = Chalk::IR::Node::HashStore->new(
        inputs => [$hash->id, $key1->id, $sum->id],
        hash_id => $hash->id,
        key_id => $key1->id,
        value_id => $sum->id,
    );

    my $key2 = Chalk::IR::Node::Constant->new(value => 'diff', type => 'string');
    my $diff = Chalk::IR::Node::Subtract->new(left => $c1, right => $c2);

    my $store2 = Chalk::IR::Node::HashStore->new(
        inputs => [$store1->id, $key2->id, $diff->id],
        hash_id => $store1->id,
        key_id => $key2->id,
        value_id => $diff->id,
    );

    my $load1 = Chalk::IR::Node::HashLoad->new(
        inputs => [$store2->id, $key1->id],
        hash_id => $store2->id,
        key_id => $key1->id,
    );
    my $load2 = Chalk::IR::Node::HashLoad->new(
        inputs => [$store2->id, $key2->id],
        hash_id => $store2->id,
        key_id => $key2->id,
    );

    my $result_mul = Chalk::IR::Node::Multiply->new(left => $load1, right => $load2);

    my $ret = Chalk::IR::Node::Return->new(
        control => $start,
        value => $result_mul,
    );

    $graph->add_node($start);
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
