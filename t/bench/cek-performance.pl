# ABOUTME: Benchmark suite for Chalk compiler performance measurement
# ABOUTME: Compares Chalk (via CEKDataflow) vs native Perl 5.42.0 execution across various program patterns
use 5.42.0;
use utf8;
use lib 'lib';
use Time::HiRes qw(time);
use File::Temp;
use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Semiring::Semantic;
use Chalk::IR::Builder;
use Chalk::IR::Optimizer::GVN;
use Chalk::Interpreter::CEKDataflow;

# Load Chalk grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Execute code via Perl 5.42.0
sub execute_perl {
    my ($code) = @_;

    # Wrap code in a subroutine so 'return' works
    my $wrapped_code = "use v5.42;\nsub main { $code }\nmy \$result = main();\nprint \$result;\n";

    # Create temporary file
    my $tmpfile = File::Temp->new(SUFFIX => '.pl');
    print $tmpfile $wrapped_code;
    close $tmpfile;

    # Execute with Perl 5.42.0
    my $output = `PLENV_VERSION=5.42.0 plenv exec perl $tmpfile 2>&1`;
    chomp $output;

    # Extract numeric return value if possible
    if ($output =~ /^-?\d+(?:\.\d+)?$/) {
        return 0 + $output;  # Convert to number
    }

    return $output;
}

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

    # Benchmark native Perl 5.42.0
    my $perl_start = time();
    for (1..$iterations) {
        execute_perl($code);
    }
    my $perl_elapsed = time() - $perl_start;
    my $perl_per_iter = $perl_elapsed / $iterations;

    # Benchmark Chalk via subprocess (using bin/chalk-exec.pl, same as Perl for fair comparison)
    my $cek_start = time();
    for (1..$iterations) {
        my $output = `PLENV_VERSION=5.42.0 plenv exec perl bin/chalk-exec.pl '$code' 2>&1`;
        chomp $output;
    }
    my $cek_elapsed = time() - $cek_start;
    my $cek_per_iter = $cek_elapsed / $iterations;

    # Calculate slowdown ratio (CEK vs Perl)
    # Higher ratio means CEK is slower
    my $ratio = $cek_per_iter / $perl_per_iter;
    my $ratio_str = sprintf("%.2fx", $ratio);

    printf("%-40s | Nodes: %3d | Perl: %8.6fs | Chalk: %8.6fs | %s\n",
        $name, $node_count, $perl_per_iter, $cek_per_iter, $ratio_str);

    return {
        name => $name,
        nodes => $node_count,
        perl_time => $perl_per_iter,
        cek_time => $cek_per_iter,
        ratio => $ratio,
    };
}

# Test cases with varying complexity
my @test_cases = (
    # Simple constant
    ["Constant", 'return 42;', 1],

    # Arithmetic operations
    ["Simple Addition", 'return 5 + 3;', 1],
    ["Complex Arithmetic", 'return (10 + 5) * (8 - 3);', 1],
    ["Chain Addition", 'return 1 + 2 + 3 + 4 + 5;', 1],

    # Variables
    ["Single Variable", 'my $x = 42; return $x;', 1],
    ["Variable Arithmetic", 'my $x = 10; my $y = 5; return $x + $y;', 1],
    ["Reassignment", 'my $x = 5; $x = 10; return $x;', 1],
    ["Multiple Reassignments", 'my $x = 1; $x = 2; $x = 3; $x = 4; return $x;', 1],

    # Comparisons
    ["Simple Comparison", 'return 10 > 5;', 1],
    ["Variable Comparison", 'my $x = 10; my $y = 5; return $x > $y;', 1],

    # Control flow (note: IR builder has bugs, but we're testing performance)
    ["If Statement", 'my $x = 5; my $r = 0; if ($x > 0) { $r = 10; } return $r;', 1],
    ["If-Else", 'my $x = 5; if ($x > 0) { return 10; } else { return 20; }', 1],
    ["Nested Variables in If", 'my $x = 10; if ($x > 5) { $x = $x + 5; } return $x;', 1],
);

# Run benchmarks
say "=" x 120;
say "Chalk Performance Benchmark (vs Native Perl 5.42.0)";
say "=" x 120;
printf("%-40s | %-9s | %-14s | %-14s | %s\n", "Test Case", "IR Nodes", "Perl Time", "Chalk Time", "Ratio");
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
my $avg_ratio = 0;
my $best_case = $results[0];    # Lowest ratio (closest to native)
my $worst_case = $results[0];   # Highest ratio (furthest from native)

foreach my $r (@results) {
    $avg_ratio += $r->{ratio};
    $best_case = $r if $r->{ratio} < $best_case->{ratio};
    $worst_case = $r if $r->{ratio} > $worst_case->{ratio};
}

$avg_ratio /= $total_cases if $total_cases > 0;

say "\nSummary:";
say sprintf("  Total test cases: %d", $total_cases);
say sprintf("  Average overhead: %.2fx (Chalk is %.0f%% slower than native Perl)",
    $avg_ratio, ($avg_ratio - 1.0) * 100);
say sprintf("  Best case: %s (%.2fx)", $best_case->{name}, $best_case->{ratio});
say sprintf("  Worst case: %s (%.2fx)", $worst_case->{name}, $worst_case->{ratio});
