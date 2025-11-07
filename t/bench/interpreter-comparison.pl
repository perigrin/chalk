#!/usr/bin/env perl
# ABOUTME: Benchmark comparing old IR::Interpreter vs new CEKDataflow interpreter
# ABOUTME: Executes identical IR graphs through both interpreters to isolate interpreter overhead
use 5.42.0;
use utf8;
use lib 'lib';
use Time::HiRes qw(time);
use Chalk::IR::Graph;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::GT;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Proj;
use Chalk::IR::Node::Region;
use Chalk::IR::Node::Phi;
use Chalk::IR::Node::Return;
use Chalk::Interpreter::CEKDataflow;

# Load old interpreter from git history
# Note: Context is still compatible, so we use the current one
BEGIN {
    system("git show 36a4476510^:lib/Chalk/IR/Interpreter.pm > /tmp/Interpreter_old.pm 2>&1");

    # Current Chalk::IR::Context is compatible with old interpreter
    # Load old Interpreter
    require "/tmp/Interpreter_old.pm";
}

# Create IR graph for: 5 + 3
sub create_arithmetic_graph {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $c1 = Chalk::IR::Node::Constant->new(id => 'node_1', value => 5, inputs => [], type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(id => 'node_2', value => 3, inputs => [], type => 'int');
    my $add = Chalk::IR::Node::Add->new(id => 'node_3', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');
    my $ret = Chalk::IR::Node::Return->new(id => 'node_4', inputs => ['node_0', 'node_3'], value_id => 'node_3', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($add);
    $graph->add_node($ret);

    return $graph;
}

# Create IR graph for: 1 + 2 + 3 + 4 + 5 (chain of additions)
sub create_chain_graph {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $c1 = Chalk::IR::Node::Constant->new(id => 'node_1', value => 1, inputs => [], type => 'int');
    my $c2 = Chalk::IR::Node::Constant->new(id => 'node_2', value => 2, inputs => [], type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(id => 'node_3', value => 3, inputs => [], type => 'int');
    my $c4 = Chalk::IR::Node::Constant->new(id => 'node_4', value => 4, inputs => [], type => 'int');
    my $c5 = Chalk::IR::Node::Constant->new(id => 'node_5', value => 5, inputs => [], type => 'int');

    my $add1 = Chalk::IR::Node::Add->new(id => 'node_6', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');
    my $add2 = Chalk::IR::Node::Add->new(id => 'node_7', inputs => ['node_6', 'node_3'], left_id => 'node_6', right_id => 'node_3');
    my $add3 = Chalk::IR::Node::Add->new(id => 'node_8', inputs => ['node_7', 'node_4'], left_id => 'node_7', right_id => 'node_4');
    my $add4 = Chalk::IR::Node::Add->new(id => 'node_9', inputs => ['node_8', 'node_5'], left_id => 'node_8', right_id => 'node_5');

    my $ret = Chalk::IR::Node::Return->new(id => 'node_10', inputs => ['node_0', 'node_9'], value_id => 'node_9', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($c1);
    $graph->add_node($c2);
    $graph->add_node($c3);
    $graph->add_node($c4);
    $graph->add_node($c5);
    $graph->add_node($add1);
    $graph->add_node($add2);
    $graph->add_node($add3);
    $graph->add_node($add4);
    $graph->add_node($ret);

    return $graph;
}

# Create IR graph for: if (10 > 5) { return 42; } else { return 0; }
sub create_if_else_graph {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $c10 = Chalk::IR::Node::Constant->new(id => 'node_1', value => 10, inputs => [], type => 'int');
    my $c5 = Chalk::IR::Node::Constant->new(id => 'node_2', value => 5, inputs => [], type => 'int');
    my $gt = Chalk::IR::Node::GT->new(id => 'node_3', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');

    my $if_node = Chalk::IR::Node::If->new(id => 'node_4', inputs => ['node_3'], condition_id => 'node_3');
    my $proj_false = Chalk::IR::Node::Proj->new(id => 'node_5', inputs => ['node_4'], index => 0, label => 'IfFalse');
    my $proj_true = Chalk::IR::Node::Proj->new(id => 'node_6', inputs => ['node_4'], index => 1, label => 'IfTrue');

    my $c42 = Chalk::IR::Node::Constant->new(id => 'node_7', value => 42, inputs => [], type => 'int');
    my $c0 = Chalk::IR::Node::Constant->new(id => 'node_8', value => 0, inputs => [], type => 'int');

    my $region = Chalk::IR::Node::Region->new(id => 'node_9', inputs => ['node_5', 'node_6']);
    my $phi = Chalk::IR::Node::Phi->new(id => 'node_10', inputs => ['node_9', 'node_8', 'node_7'],
        region_id => 'node_9');

    my $ret = Chalk::IR::Node::Return->new(id => 'node_11', inputs => ['node_0', 'node_10'], value_id => 'node_10', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($c10);
    $graph->add_node($c5);
    $graph->add_node($gt);
    $graph->add_node($if_node);
    $graph->add_node($proj_false);
    $graph->add_node($proj_true);
    $graph->add_node($c42);
    $graph->add_node($c0);
    $graph->add_node($region);
    $graph->add_node($phi);
    $graph->add_node($ret);

    return $graph;
}

# Create IR graph for: (10 + 5) * (8 - 3)
sub create_complex_graph {
    my $graph = Chalk::IR::Graph->new();

    my $start = Chalk::IR::Node::Start->new(id => 'node_0', inputs => [], function_name => 'test', params => []);
    my $c10 = Chalk::IR::Node::Constant->new(id => 'node_1', value => 10, inputs => [], type => 'int');
    my $c5 = Chalk::IR::Node::Constant->new(id => 'node_2', value => 5, inputs => [], type => 'int');
    my $c8 = Chalk::IR::Node::Constant->new(id => 'node_3', value => 8, inputs => [], type => 'int');
    my $c3 = Chalk::IR::Node::Constant->new(id => 'node_4', value => 3, inputs => [], type => 'int');

    my $add = Chalk::IR::Node::Add->new(id => 'node_5', inputs => ['node_1', 'node_2'], left_id => 'node_1', right_id => 'node_2');
    my $sub = Chalk::IR::Node::Subtract->new(id => 'node_6', inputs => ['node_3', 'node_4'], left_id => 'node_3', right_id => 'node_4');
    my $mul = Chalk::IR::Node::Multiply->new(id => 'node_7', inputs => ['node_5', 'node_6'], left_id => 'node_5', right_id => 'node_6');

    my $ret = Chalk::IR::Node::Return->new(id => 'node_8', inputs => ['node_0', 'node_7'], value_id => 'node_7', control_id => 'node_0');

    $graph->add_node($start);
    $graph->add_node($c10);
    $graph->add_node($c5);
    $graph->add_node($c8);
    $graph->add_node($c3);
    $graph->add_node($add);
    $graph->add_node($sub);
    $graph->add_node($mul);
    $graph->add_node($ret);

    return $graph;
}

# Benchmark old interpreter on a graph (creates fresh interpreter each time)
sub benchmark_old_interpreter {
    my ($graph, $iterations) = @_;

    my $elapsed = 0;
    for (1..$iterations) {
        my $interp = Chalk::IR::Interpreter->new(graph => $graph);
        my $start = time();
        $interp->execute();
        $elapsed += time() - $start;
    }

    return $elapsed / $iterations;
}

# Benchmark CEK interpreter on a graph (creates fresh interpreter each time)
sub benchmark_cek_interpreter {
    my ($graph, $iterations) = @_;

    my $elapsed = 0;
    for (1..$iterations) {
        my $interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
        my $start = time();
        $interp->execute();
        $elapsed += time() - $start;
    }

    return $elapsed / $iterations;
}

# Run comparative benchmark
sub compare_interpreters {
    my ($test_name, $graph, $iterations) = @_;

    my $node_count = scalar keys $graph->nodes->%*;

    # Create fresh interpreters for each test
    my $old_interp = Chalk::IR::Interpreter->new(graph => $graph);
    my $cek_interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);

    # Verify both produce same result
    my $old_result = $old_interp->execute();

    # Create new CEK interpreter since execute() mutates state
    $cek_interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $cek_result = $cek_interp->execute();

    unless ($old_result == $cek_result) {
        die "ERROR: Results differ for $test_name! Old: $old_result, CEK: $cek_result";
    }

    # Benchmark both interpreters
    my $old_time = benchmark_old_interpreter($graph, $iterations);
    my $cek_time = benchmark_cek_interpreter($graph, $iterations);

    # Calculate ratio (CEK / Old)
    my $ratio = $cek_time / $old_time;

    return {
        test => $test_name,
        nodes => $node_count,
        old_time => $old_time,
        cek_time => $cek_time,
        ratio => $ratio,
        result => $old_result,
    };
}

# Main benchmark suite
binmode(STDOUT, ':utf8');
say "=" x 100;
say "Interpreter Comparison: Old IR::Interpreter vs New CEKDataflow";
say "=" x 100;
say "Purpose: Isolate interpreter overhead by comparing execution on identical IR graphs";
say "Context: PR #164 reviewer questioned whether 87x overhead is parsing or CEK interpreter";
say "=" x 100;
printf("%-25s | Nodes | Old (us)  | CEK (us)  | Ratio    | Result\n", "Test Case");
say "-" x 100;

my @test_cases = (
    ["Simple Arithmetic", \&create_arithmetic_graph, 10000],
    ["Chain Addition", \&create_chain_graph, 10000],
    ["If/Else Control Flow", \&create_if_else_graph, 5000],
    ["Complex Expression", \&create_complex_graph, 10000],
);

my @results;
foreach my $test (@test_cases) {
    my ($name, $graph_builder, $iterations) = $test->@*;
    my $graph = $graph_builder->();
    my $result = compare_interpreters($name, $graph, $iterations);
    push @results, $result;

    printf("%-25s | %5d | %9.2f | %9.2f | %7.3fx | %d\n",
        $result->{test},
        $result->{nodes},
        $result->{old_time} * 1_000_000,  # Convert to microseconds
        $result->{cek_time} * 1_000_000,
        $result->{ratio},
        $result->{result});
}

say "=" x 100;

# Summary analysis
my $total = scalar(@results);
my $sum_ratio = 0;
my $min_ratio = $results[0]->{ratio};
my $max_ratio = $results[0]->{ratio};
my $min_test = $results[0]->{test};
my $max_test = $results[0]->{test};

foreach my $r (@results) {
    $sum_ratio += $r->{ratio};
    if ($r->{ratio} < $min_ratio) {
        $min_ratio = $r->{ratio};
        $min_test = $r->{test};
    }
    if ($r->{ratio} > $max_ratio) {
        $max_ratio = $r->{ratio};
        $max_test = $r->{test};
    }
}

my $avg_ratio = $sum_ratio / $total;

say "\nAnalysis:";
say sprintf("  Average ratio: %.3fx (CEK is %.1f%% %s than old interpreter)",
    $avg_ratio,
    abs($avg_ratio - 1.0) * 100,
    $avg_ratio > 1.0 ? "slower" : "faster");
say sprintf("  Best case: %s (%.3fx)", $min_test, $min_ratio);
say sprintf("  Worst case: %s (%.3fx)", $max_test, $max_ratio);

say "\nConclusion:";
if ($avg_ratio <= 0.9) {
    say "  ✓ CEK interpreter is FASTER than old interpreter (" . sprintf("%.1f%%", (1.0 - $avg_ratio) * 100) . " faster)";
    say "  ✓ This STRONGLY supports the claim that 87x overhead is dominated by PARSING, not CEK execution";
    say "  ✓ The new interpreter architecture actually improves performance over the old one";
} elsif ($avg_ratio < 1.1) {
    say "  ✓ CEK interpreter performance is COMPARABLE to old interpreter (within 10%)";
    say "  ✓ This supports the claim that 87x overhead is dominated by PARSING, not CEK execution";
} elsif ($avg_ratio < 2.0) {
    say "  ⚠ CEK interpreter is moderately slower (${avg_ratio}x) than old interpreter";
    say "  ⚠ Some of the 87x overhead comes from CEK, but parsing likely still dominates";
} else {
    say "  ✗ CEK interpreter is significantly slower (${avg_ratio}x) than old interpreter";
    say "  ✗ CEK performance may contribute meaningfully to the 87x overhead";
}

say "\nNote: Old interpreter linearizes graph once, CEK uses dataflow scheduling";
say "      Both use the same context-threading model for value lookup";

# Cleanup
unlink "/tmp/Interpreter_old.pm";
