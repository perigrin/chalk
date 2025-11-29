#!/usr/bin/env perl
# ABOUTME: SPPF-level test for issue #195 statement sequencing
# ABOUTME: Verifies parse forest creates correct alternatives WITHOUT semantic evaluation

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::SPPF;

# Load Chalk grammar
open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

subtest 'Issue #195: Early return statement sequencing - SPPF structure' => sub {
    # Test case: my $x = -5; if ($x > 0) { return 42; } return -42;
    # Expected: Should parse as 3 statements:
    #   1. my $x = -5;
    #   2. if ($x > 0) { return 42; }
    #   3. return -42;

    my $code = 'my $x = -5; if ($x > 0) { return 42; } return -42;';

    # Parse with SPPF semiring to capture parse forest
    my $sppf = Chalk::Semiring::SPPF->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf
    );

    my $result = $parser->parse_string($code);
    ok $result, 'Code parses successfully';

    SKIP: {
        skip 'Parse failed' unless $result;

        my $forest = $sppf->forest;
        ok $forest, 'SPPF forest exists';

        # Find StatementList node spanning entire program (after WS_OPT)
        my @statement_lists = grep {
            $_->isa('Chalk::ParseForest::SymbolNode') &&
            $_->symbol eq 'StatementList' &&
            $_->start_pos == 0 &&
            $_->end_pos == length($code)
        } values %{$forest->nodes};

        ok scalar(@statement_lists) > 0, 'Found StatementList node(s) covering full input';

        if (@statement_lists) {
            my $root_stmtlist = $statement_lists[0];
            note("StatementList at [" . $root_stmtlist->start_pos . "," . $root_stmtlist->end_pos . "]");

            my @packed = $root_stmtlist->packed_nodes;
            my $num_alternatives = scalar(@packed);
            note("Root StatementList has $num_alternatives alternative(s)");

            # CRITICAL: We need AT LEAST 2 alternatives for disambiguation
            ok $num_alternatives >= 2, 'StatementList has multiple alternatives (needed for disambiguation)';

            # Analyze each alternative's structure
            for my $i (0..$#packed) {
                my $packed = $packed[$i];
                my $rule = $packed->rule;

                if ($rule) {
                    note("  Alternative $i: " . $rule->to_string);
                }
            }
        }
    }
};

subtest 'Baseline: Simple statement sequence - SPPF structure' => sub {
    # Working case: my $x = 1; $x = 2; $x = 3; return $x;
    # This should parse correctly as 4 statements

    my $code = 'my $x = 1; $x = 2; $x = 3; return $x;';

    my $sppf = Chalk::Semiring::SPPF->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf
    );

    my $result = $parser->parse_string($code);
    ok $result, 'Baseline code parses successfully';

    SKIP: {
        skip 'Parse failed' unless $result;

        my $forest = $sppf->forest;
        my @statement_lists = grep {
            $_->isa('Chalk::ParseForest::SymbolNode') &&
            $_->symbol eq 'StatementList' &&
            $_->start_pos == 0 &&
            $_->end_pos == length($code)
        } values %{$forest->nodes};

        if (@statement_lists) {
            my $root_stmtlist = $statement_lists[0];
            my @packed = $root_stmtlist->packed_nodes;
            note("Baseline StatementList has " . scalar(@packed) . " alternative(s)");
        }
    }
};
