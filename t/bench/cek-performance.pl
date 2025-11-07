# ABOUTME: Benchmark suite for CEK interpreter performance measurement
# ABOUTME: Compares CEKDataflow vs reference IR::Interpreter across various program patterns
use 5.42.0;
use utf8;
use lib 'lib';
use Time::HiRes qw(time);
use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Semiring::Semantic;
use Chalk::IR::Builder;
use Chalk::IR::Interpreter;
use Chalk::IR::Optimizer::GVN;
use Chalk::Interpreter::CEKDataflow;

# Load Chalk grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Compile Chalk code to IR graph
sub compile_chalk {
    my ($code) = @_;

    my $builder = Chalk::IR::Builder->new();
    my $semiring = Chalk::Semiring::Semantic->new(
        grammar => $grammar,
        env => { ir_builder => $builder }
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $parse_result = eval { $parser->parse_string($code) };
    return undef if $@ || !$parse_result;

    my $graph = $builder->graph;

    # Prune to winning parse
    if ($parse_result->can('context')) {
        my $ctx = $parse_result->context;
        if ($ctx->can('focus')) {
            my $winning_node = $ctx->focus;
            if ($winning_node && $winning_node->can('id')) {
                eval { $graph->prune_to_reachable($winning_node->id) };
                return undef if $@;
            }
        }
    }

    # Run GVN optimizer
    my $gvn_result = eval { Chalk::IR::Optimizer::GVN->run_gvn($graph) };
    return undef if $@ || !$gvn_result;

    return $gvn_result->{graph};
}

# Benchmark a single test case
sub benchmark_case {
    my ($name, $code, $iterations) = @_;

    # Compile once
    my $graph = compile_chalk($code);
    unless ($graph) {
        say "SKIP $name: compilation failed";
        return;
    }

    # Count nodes in graph
    my $node_count = scalar keys $graph->nodes->%*;

    # Benchmark reference interpreter
    my $ref_start = time();
    for (1..$iterations) {
        my $ref_interp = Chalk::IR::Interpreter->new(graph => $graph);
        $ref_interp->execute();
    }
    my $ref_elapsed = time() - $ref_start;
    my $ref_per_iter = $ref_elapsed / $iterations;

    # Benchmark CEK interpreter
    my $cek_start = time();
    for (1..$iterations) {
        my $cek_interp = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
        $cek_interp->execute();
    }
    my $cek_elapsed = time() - $cek_start;
    my $cek_per_iter = $cek_elapsed / $iterations;

    # Calculate speedup (negative means CEK is slower)
    my $speedup = $ref_per_iter / $cek_per_iter;
    my $speedup_str = sprintf("%.2fx", $speedup);
    if ($speedup < 1.0) {
        $speedup_str = sprintf("%.2fx slower", 1.0 / $speedup);
    } elsif ($speedup > 1.0) {
        $speedup_str = sprintf("%.2fx faster", $speedup);
    } else {
        $speedup_str = "same";
    }

    printf("%-40s | Nodes: %3d | Ref: %8.6fs | CEK: %8.6fs | %s\n",
        $name, $node_count, $ref_per_iter, $cek_per_iter, $speedup_str);

    return {
        name => $name,
        nodes => $node_count,
        ref_time => $ref_per_iter,
        cek_time => $cek_per_iter,
        speedup => $speedup,
    };
}

# Test cases with varying complexity
my @test_cases = (
    # Simple constant
    ["Constant", 'return 42;', 10000],

    # Arithmetic operations
    ["Simple Addition", 'return 5 + 3;', 10000],
    ["Complex Arithmetic", 'return (10 + 5) * (8 - 3);', 10000],
    ["Chain Addition", 'return 1 + 2 + 3 + 4 + 5;', 10000],

    # Variables
    ["Single Variable", 'my $x = 42; return $x;', 10000],
    ["Variable Arithmetic", 'my $x = 10; my $y = 5; return $x + $y;', 10000],
    ["Reassignment", 'my $x = 5; $x = 10; return $x;', 10000],
    ["Multiple Reassignments", 'my $x = 1; $x = 2; $x = 3; $x = 4; return $x;', 10000],

    # Comparisons
    ["Simple Comparison", 'return 10 > 5;', 10000],
    ["Variable Comparison", 'my $x = 10; my $y = 5; return $x > $y;', 10000],

    # Control flow (note: IR builder has bugs, but we're testing performance)
    ["If Statement", 'my $x = 5; my $r = 0; if ($x > 0) { $r = 10; } return $r;', 5000],
    ["If-Else", 'my $x = 5; if ($x > 0) { return 10; } else { return 20; }', 5000],
    ["Nested Variables in If", 'my $x = 10; if ($x > 5) { $x = $x + 5; } return $x;', 5000],
);

# Run benchmarks
say "=" x 120;
say "CEK Interpreter Performance Benchmark";
say "=" x 120;
printf("%-40s | %-9s | %-14s | %-14s | %s\n", "Test Case", "IR Nodes", "Ref Time", "CEK Time", "Speedup");
say "-" x 120;

my @results;
foreach my $test (@test_cases) {
    my ($name, $code, $iters) = $test->@*;
    my $result = benchmark_case($name, $code, $iters);
    push @results, $result if $result;
}

say "=" x 120;

# Summary statistics
my $total_cases = scalar(@results);
my $avg_speedup = 0;
my $fastest_case = $results[0];
my $slowest_case = $results[0];

foreach my $r (@results) {
    $avg_speedup += $r->{speedup};
    $fastest_case = $r if $r->{speedup} > $fastest_case->{speedup};
    $slowest_case = $r if $r->{speedup} < $slowest_case->{speedup};
}

$avg_speedup /= $total_cases if $total_cases > 0;

say "\nSummary:";
say sprintf("  Total test cases: %d", $total_cases);
say sprintf("  Average speedup: %.2fx", $avg_speedup);
say sprintf("  Fastest case: %s (%.2fx)", $fastest_case->{name}, $fastest_case->{speedup});
say sprintf("  Slowest case: %s (%.2fx)", $slowest_case->{name}, $slowest_case->{speedup});

if ($avg_speedup > 1.0) {
    say sprintf("\n  CEK is %.2fx faster than reference interpreter on average", $avg_speedup);
} elsif ($avg_speedup < 1.0) {
    say sprintf("\n  CEK is %.2fx slower than reference interpreter on average", 1.0 / $avg_speedup);
} else {
    say "\n  CEK and reference interpreter have similar performance";
}
