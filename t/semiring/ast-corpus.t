#!/usr/bin/env perl
# ABOUTME: Tests AST semiring output against expected corpus files
# ABOUTME: Compares parsed AST JSON against pre-recorded expected output

use 5.42.0;
use lib 'lib';
use Test::More;
use JSON::PP ();
use FindBin qw($RealBin);
use File::Basename qw(basename);

use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::AST;
use Chalk::Semiring::ChalkSyntax;
use Chalk::Semiring::Composite;

# Check if t/corpus/ast/* was modified in this branch/PR
# If not, skip the expensive corpus test
my $corpus_changed = 0;

# If FORCE_AST_CORPUS env var is set, always run
if ($ENV{FORCE_AST_CORPUS}) {
    $corpus_changed = 1;
    diag "FORCE_AST_CORPUS set - running full AST corpus test";
} elsif (-d "$RealBin/../../.git") {
    # Get the merge base with the target branch (pu)
    my $merge_base = `git -C "$RealBin/../.." merge-base HEAD origin/pu 2>/dev/null`;
    chomp $merge_base;

    if ($merge_base) {
        # Check if any files in t/corpus/ast/ changed since the merge base
        my $changed_files = `git -C "$RealBin/../.." diff --name-only $merge_base HEAD 2>/dev/null`;
        $corpus_changed = 1 if $changed_files =~ m{^t/corpus/ast/}m;
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
    pass "No changes to t/corpus/ast/* detected - skipping expensive corpus test";
    diag "AST corpus test skipped: t/corpus/ast/ unchanged since merge-base with origin/pu";
    diag "To force running: FORCE_AST_CORPUS=1 prove t/semiring/ast-corpus.t";
    exit 0;
}

diag "t/corpus/ast/* changed detected - running full AST corpus test";

# Load grammar once
my $grammar;
BEGIN {
    open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
    my $bnf_content = do { local $/; <$fh> };
    close $fh;
    $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');
}

# Helper to parse and get AST
sub parse_to_ast($input) {
    my $chalksyntax = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
    my $ast = Chalk::Semiring::AST->new();
    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$chalksyntax, $ast]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $result = $parser->parse_string($input);
    return undef unless $result;

    # Extract AST element from composite
    if ($result->can('elements')) {
        my @elements = $result->elements->@*;
        return $elements[1] if @elements > 1;
    }

    return $result;
}

# Normalize AST by removing spans (for comparison without position sensitivity)
sub normalize_ast($node) {
    return $node unless ref($node) eq 'HASH';

    my $result = { rule => $node->{rule} };

    if (exists $node->{children}) {
        $result->{children} = [
            map { normalize_ast($_) } $node->{children}->@*
        ];
    }

    return $result;
}

# Find all corpus test cases
my $corpus_dir = "$RealBin/../corpus/ast";
my @test_cases = glob("$corpus_dir/*.chalk");

if (@test_cases == 0) {
    plan skip_all => 'No corpus test cases found';
}

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

        # Read input
        open my $fh, '<:utf8', $chalk_file or die "Cannot read $chalk_file: $!";
        my $input = do { local $/; <$fh> };
        close $fh;

        # Parse
        my $ast = parse_to_ast($input);
        ok($ast, "Parsed $test_name") or return;

        # Get actual output
        my $actual_hash = $ast->to_hash();

        # Read expected output
        open $fh, '<:utf8', $json_file or die "Cannot read $json_file: $!";
        my $expected_json = do { local $/; <$fh> };
        close $fh;
        my $expected_hash = JSON::PP->new->decode($expected_json);

        # Compare normalized (without spans)
        my $actual_normalized = normalize_ast($actual_hash);
        my $expected_normalized = normalize_ast($expected_hash);

        is_deeply($actual_normalized, $expected_normalized, "AST structure matches for $test_name")
            or diag("Actual: " . JSON::PP->new->pretty->canonical->encode($actual_hash));
    };
}

done_testing();
