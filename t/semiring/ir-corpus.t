#!/usr/bin/env perl
# ABOUTME: Tests IR generation semiring output against expected corpus files
# ABOUTME: Compares parsed Sea of Nodes IR JSON against pre-recorded expected output

use 5.42.0;
use lib 'lib';
use Test::More;
use JSON::PP ();
use FindBin qw($RealBin);
use File::Basename qw(basename);

use Chalk::Grammar;
use Chalk::Grammar::Chalk;  # Pre-load Chalk rule classes for semantic actions
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;

# Check if t/corpus/ir/* was modified in this branch/PR
# If not, skip the expensive corpus test
my $corpus_changed = 0;

# If FORCE_IR_CORPUS env var is set, always run
if ($ENV{FORCE_IR_CORPUS}) {
    $corpus_changed = 1;
    diag "FORCE_IR_CORPUS set - running full IR corpus test";
} elsif (-d "$RealBin/../../.git") {
    # Get the merge base with the target branch (pu)
    my $merge_base = `git -C "$RealBin/../.." merge-base HEAD origin/pu 2>/dev/null`;
    chomp $merge_base;

    if ($merge_base) {
        # Check if any files in t/corpus/ir/ changed since the merge base
        my $changed_files = `git -C "$RealBin/../.." diff --name-only $merge_base HEAD 2>/dev/null`;
        $corpus_changed = 1 if $changed_files =~ m{^t/corpus/ir/}m;
    } else {
        # Fallback: If we can't determine merge base, assume corpus changed
        $corpus_changed = 1;
    }
} else {
    # Not in a git repo, run the tests
    $corpus_changed = 1;
}

unless ($corpus_changed) {
    plan tests => 1;
    pass "No changes to t/corpus/ir/* detected - skipping expensive corpus test";
    diag "IR corpus test skipped: t/corpus/ir/ unchanged since merge-base with origin/pu";
    diag "To force running: FORCE_IR_CORPUS=1 prove t/semiring/ir-corpus.t";
    exit 0;
}

diag "t/corpus/ir/* changed detected - running full IR corpus test";

# Load grammar once
my $grammar;
BEGIN {
    open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
    my $bnf_content = do { local $/; <$fh> };
    close $fh;
    $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');
}

# Helper to parse and get IR graph
sub parse_to_ir($input) {
    my $ir_semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $ir_semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $result = $parser->parse_string($input);
    return undef unless $result;

    my $builder = $ir_semiring->builder;
    my $graph = $builder->graph;

    # Prune to winning parse if possible
    if ($result->can('context')) {
        my $ctx = $result->context;
        if ($ctx && $ctx->can('focus')) {
            my $focus = $ctx->focus;
            if ($focus && $focus->can('id')) {
                eval { $graph->prune_to_reachable($focus->id) };
                return undef if $@;
            }
        }
    }

    return $graph;
}

# Normalize IR by sorting nodes for stable comparison
sub normalize_ir($ir_hash) {
    return $ir_hash unless ref($ir_hash) eq 'HASH';

    my $result = {
        version => $ir_hash->{version},
        entry => $ir_hash->{entry}
    };

    # Sort nodes by id for stable comparison
    if (exists $ir_hash->{nodes}) {
        my @sorted_nodes = sort { $a->{id} cmp $b->{id} } $ir_hash->{nodes}->@*;
        $result->{nodes} = \@sorted_nodes;
    }

    return $result;
}

# Find all corpus test cases
my $corpus_dir = "$RealBin/../corpus/ir";
my @test_cases = glob("$corpus_dir/*.chalk");

if (@test_cases == 0) {
    plan skip_all => 'No corpus test cases found';
}

# Known failing tests due to incomplete IR generation
# (currently all tests pass after fixing test cases to use valid expressions)
my %todo_tests = ();

# Run tests for each corpus entry
for my $chalk_file (sort @test_cases) {
    my $test_name = basename($chalk_file, '.chalk');
    my $json_file = $chalk_file =~ s/\.chalk$/.json/r;

    subtest "Corpus: $test_name" => sub {
        # Skip if no expected output
        unless (-f $json_file) {
            plan skip_all => "No expected output for $test_name";
            return;
        }

        # Mark TODO tests
        if ($todo_tests{$test_name}) {
            TODO: {
                local $TODO = "Control flow IR generation incomplete";
                run_ir_test($chalk_file, $json_file, $test_name);
            }
        } else {
            run_ir_test($chalk_file, $json_file, $test_name);
        }
    };
}

sub run_ir_test($chalk_file, $json_file, $test_name) {
    # Read input
    open my $fh, '<:utf8', $chalk_file or die "Cannot read $chalk_file: $!";
    my $input = do { local $/; <$fh> };
    close $fh;

    # Parse
    my $graph = parse_to_ir($input);
    ok($graph, "Parsed $test_name") or return;

    # Get actual output
    my $actual_hash = $graph->to_json();

    # Read expected output
    open $fh, '<:utf8', $json_file or die "Cannot read $json_file: $!";
    my $expected_json = do { local $/; <$fh> };
    close $fh;
    my $expected_hash = JSON::PP->new->decode($expected_json);

    # Compare normalized
    my $actual_normalized = normalize_ir($actual_hash);
    my $expected_normalized = normalize_ir($expected_hash);

    is_deeply($actual_normalized, $expected_normalized, "IR structure matches for $test_name")
        or diag("Actual: " . JSON::PP->new->pretty->canonical->allow_blessed->convert_blessed->encode($actual_hash));
}

done_testing();
