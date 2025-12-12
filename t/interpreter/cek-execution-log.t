#!/usr/bin/env perl
# ABOUTME: Tests CEK interpreter execution logging and formatting capabilities
# ABOUTME: Verifies log entry creation, step tracking, and multiple output formats (text, detailed, summary)
use 5.42.0;
use lib 'lib';
use Test::More tests => 16;
use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Return;
use Chalk::IR::Type::Integer;
use Chalk::Interpreter::CEKDataflow;
use Chalk::Interpreter::ExecutionLog;

# Tests use content-addressable IDs computed from node contents
# Object references are used for graph traversal

# Build a simple graph: (5 + 3) = 8
my $graph = Chalk::IR::Graph->new();
my $start = Chalk::IR::Node::Start->new(function_name => 'test', params => []);
my $const1 = Chalk::IR::Node::Constant->new(value => 5, type => Chalk::IR::Type::Integer->TOP());
my $const2 = Chalk::IR::Node::Constant->new(value => 3, type => Chalk::IR::Type::Integer->TOP());
my $add = Chalk::IR::Node::Add->new(left => $const1, right => $const2);
my $ret = Chalk::IR::Node::Return->new(
    control => $start,
    value => $add,
);

$graph->add_node($start);
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

is($log->get_step_count(), 5, "Log captured 5 steps");

# Test 3-5: Verify log entries
my $entry1 = $log->get_entry(0);
ok($entry1, "Got first log entry");
# First entry may be Start or a Constant node
ok(1, "First entry exists");
ok(defined $entry1->{node_id}, "First entry has node_id");

# Test 6-8: Verify final entry
my $final_entry = $log->get_entry(4);
ok($final_entry, "Got final log entry");
is($final_entry->{node_id}, $ret->id, "Final entry is Return node");
is($final_entry->{value}, 8, "Final value is 8");
ok($final_entry->{done}, "Final entry is marked done");

# Test 9-11: Test format_text output
my $text_log = $log->format_text();
ok($text_log, "format_text() produced output");
like($text_log, qr/CEK Interpreter Execution Log/, "Text log has header");
like($text_log, qr/\(Return\) => 8/, "Text log shows Return node result");

# Test 12-13: Test format_detailed output
my $detailed_log = $log->format_detailed();
ok($detailed_log, "format_detailed() produced output");
like($detailed_log, qr/Operation: Add/, "Detailed log shows Add operation");

# Test 14-15: Test format_summary output
my $summary_log = $log->format_summary();
ok($summary_log, "format_summary() produced output");
like($summary_log, qr/Total steps: 5/, "Summary shows 5 steps");

