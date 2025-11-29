#!/usr/bin/env perl
# ABOUTME: Test Earley parser with actual Chalk grammar for arithmetic expressions
# ABOUTME: Verifies parser generates multiple parse alternatives for "1 + 2 * 3" before precedence filtering
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use File::Spec;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;  # Pre-loads rule classes
use Chalk::Parser;
use Chalk::Semiring::SPPF;

# Load chalk.bnf grammar
my $bnf_file = File::Spec->catfile($RealBin, '../../grammar', 'chalk.bnf');
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

subtest 'Chalk grammar: Parser should generate both alternatives for "1 + 2 * 3"' => sub {

    ok $grammar, 'Chalk grammar loaded';

    # Use SPPF semiring ONLY - no precedence filtering
    my $sppf = Chalk::Semiring::SPPF->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Parse a simple return statement with ambiguous arithmetic
    my $code = 'return 1 + 2 * 3;';
    my $result = $parser->parse_string($code);

    ok $result, 'Expression parses successfully with Chalk grammar';

    SKIP: {
        skip 'Parse failed' unless $result;

        my $forest = $sppf->forest;
        ok $forest, 'SPPF forest exists';

        # Find all ArithmeticOp nodes in the forest
        my @all_nodes = values %{$forest->nodes};
        my @arith_nodes = grep { $_->symbol eq 'ArithmeticOp' } @all_nodes;

        note("Found " . scalar(@arith_nodes) . " ArithmeticOp nodes:");
        for my $node (@arith_nodes) {
            my $span = sprintf("[%d,%d]", $node->start_pos, $node->end_pos);
            my @packed = $node->packed_nodes;
            note("  ArithmeticOp$span with " . scalar(@packed) . " alternative(s)");

            # For each alternative, try to identify the operator
            for my $i (0..$#packed) {
                my $packed = $packed[$i];
                my $rule = $packed->rule;
                if ($rule) {
                    my $rhs = $rule->rhs;
                    # Look for the operator token in the RHS
                    # In Chalk grammar: ArithmeticOp -> Expression WS_OPT %ARITHMETIC_OP% WS_OPT Expression
                    # The operator is the third element (index 2)
                    if (@$rhs >= 3) {
                        my @symbols = map { ref($_) ? ref($_) : $_ } @$rhs;
                        note("    Alternative $i: RHS = " . join(', ', @symbols));
                    }
                }
            }
        }

        # Find the root ArithmeticOp node that spans "1 + 2 * 3"
        # Position depends on "return " prefix, so we look for the widest span
        my @sorted_by_span = sort {
            ($b->end_pos - $b->start_pos) <=> ($a->end_pos - $a->start_pos)
        } @arith_nodes;

        if (@sorted_by_span) {
            my $root_arith = $sorted_by_span[0];
            my $span = sprintf("[%d,%d]", $root_arith->start_pos, $root_arith->end_pos);
            my @packed = $root_arith->packed_nodes;
            my $num_alternatives = scalar(@packed);

            note("Widest ArithmeticOp span: $span with $num_alternatives alternative(s)");

            # EXPECTED: 2 alternatives
            #   Alternative 0: 1 + (2*3) - parsing as addition with multiplication inside
            #   Alternative 1: (1+2) * 3 - parsing as multiplication with addition inside
            todo 'Chalk grammar parser not generating both parse alternatives' => sub {
                cmp_ok $num_alternatives, '>=', 2,
                    'Root ArithmeticOp should have at least 2 packed alternatives';
            };
        } else {
            fail('No ArithmeticOp nodes found in parse forest');
        }
    }
};

subtest 'Chalk grammar: Examine Expression nodes for ambiguity' => sub {
    my $sppf = Chalk::Semiring::SPPF->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $code = 'return 1 + 2 * 3;';
    my $result = $parser->parse_string($code);

    ok $result, 'Parse succeeds';

    SKIP: {
        skip 'Parse failed' unless $result;

        my $forest = $sppf->forest;

        # Look at Expression nodes - these recursively contain ArithmeticOp
        my @all_nodes = values %{$forest->nodes};
        my @expr_nodes = grep { $_->symbol eq 'Expression' } @all_nodes;

        note("Found " . scalar(@expr_nodes) . " Expression nodes");

        # Find Expression nodes with multiple alternatives
        my @ambiguous_expr = grep { scalar($_->packed_nodes) > 1 } @expr_nodes;

        if (@ambiguous_expr) {
            note("Found " . scalar(@ambiguous_expr) . " ambiguous Expression nodes:");
            for my $node (@ambiguous_expr) {
                my $span = sprintf("[%d,%d]", $node->start_pos, $node->end_pos);
                my @packed = $node->packed_nodes;
                note("  Expression$span with " . scalar(@packed) . " alternatives");
            }
            pass('Parser generates multiple Expression alternatives');
        } else {
            note('No ambiguous Expression nodes - checking if this is expected');
            todo 'May need ambiguous Expression nodes for arithmetic precedence' => sub {
                ok scalar(@ambiguous_expr) > 0,
                    'Should have at least one Expression node with multiple alternatives';
            };
        }
    }
};

subtest 'Chalk grammar: Compare node counts with and without precedence' => sub {
    # Parse with SPPF only
    my $sppf_only = Chalk::Semiring::SPPF->new();
    my $parser_sppf = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf_only,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $code = 'return 1 + 2 * 3;';
    my $result_sppf = $parser_sppf->parse_string($code);

    ok $result_sppf, 'SPPF-only parse succeeds';

    SKIP: {
        skip 'Parse failed' unless $result_sppf;

        my $forest_sppf = $sppf_only->forest;
        my @arith_sppf = grep { $_->symbol eq 'ArithmeticOp' }
                         values %{$forest_sppf->nodes};

        # Count total packed alternatives across all ArithmeticOp nodes
        my $total_alternatives_sppf = 0;
        for my $node (@arith_sppf) {
            $total_alternatives_sppf += scalar($node->packed_nodes);
        }

        note("SPPF only: " . scalar(@arith_sppf) . " ArithmeticOp nodes, " .
             "$total_alternatives_sppf total packed alternatives");

        # If parser is generating both parse trees, we should see:
        # - At least 2 ArithmeticOp nodes (one for each operator)
        # - The root span should have 2+ alternatives
        cmp_ok scalar(@arith_sppf), '>=', 2,
            'Should have at least 2 ArithmeticOp nodes (one for + and one for *)';

        todo 'Total alternatives should reflect ambiguity' => sub {
            cmp_ok $total_alternatives_sppf, '>=', 4,
                'Total packed alternatives should reflect both parse trees';
        };
    }
};
