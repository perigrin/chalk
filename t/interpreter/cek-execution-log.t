use 5.42.0;
use Test::More tests => 16;
use Chalk::IR::Graph;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Return;
use Chalk::Interpreter::CEKDataflow;
use Chalk::Interpreter::ExecutionLog;

# Build a simple graph: (5 + 3) = 8
my $graph = Chalk::IR::Graph->new();
my $const1 = Chalk::IR::Node::Constant->new(id => 'node_1', inputs => [], value => 5, type => 'int');
my $const2 = Chalk::IR::Node::Constant->new(id => 'node_2', inputs => [], value => 3, type => 'int');
my $add = Chalk::IR::Node::Add->new(id => 'node_3', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');
my $ret = Chalk::IR::Node::Return->new(id => 'node_4', inputs => ['node_3'], value_id => 'node_3', control_id => 'node_3');

$graph->add_node($const1);
$graph->add_node($const2);
$graph->add_node($add);
$graph->add_node($ret);

# Test 1-2: Create execution log and capture steps
my $log = Chalk::Interpreter::ExecutionLog->new(graph => $graph);
isa_ok($log, 'Chalk::Interpreter::ExecutionLog', "ExecutionLog created");

my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
$interp->initialize_stepping();

my $step_num = 1;
while (!$interp->is_stepping_complete()) {
    my $step_report = $interp->step();
    $log->add_step($step_num++, $step_report);
    last if $step_report->{done};
}

is($log->get_step_count(), 4, "Log captured 4 steps");

# Test 3-5: Verify log entries
my $entry1 = $log->get_entry(0);
ok($entry1, "Got first log entry");
ok($entry1->{node_id} eq 'node_1' || $entry1->{node_id} eq 'node_2', "First entry is a constant node");
ok($entry1->{value} == 5 || $entry1->{value} == 3, "First entry value is 5 or 3");

# Test 6: Verify final entry
my $final_entry = $log->get_entry(3);
ok($final_entry, "Got final log entry");
is($final_entry->{node_id}, 'node_4', "Final entry is Return node");
is($final_entry->{value}, 8, "Final value is 8");
ok($final_entry->{done}, "Final entry is marked done");

# Test 9-11: Test format_text output
my $text_log = $log->format_text();
ok($text_log, "format_text() produced output");
like($text_log, qr/CEK Interpreter Execution Log/, "Text log has header");
like($text_log, qr/node_4 \(Return\) => 8/, "Text log shows Return node result");

# Test 12-13: Test format_detailed output
my $detailed_log = $log->format_detailed();
ok($detailed_log, "format_detailed() produced output");
like($detailed_log, qr/Operation: Add/, "Detailed log shows Add operation");

# Test 14-15: Test format_summary output
my $summary_log = $log->format_summary();
ok($summary_log, "format_summary() produced output");
like($summary_log, qr/Total steps: 4/, "Summary shows 4 steps");

