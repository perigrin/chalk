#!/usr/bin/env perl
# ABOUTME: Test Earley parser generation of multiple parse alternatives for ambiguous arithmetic
# ABOUTME: Verifies parser creates all valid parse trees before semiring filtering
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use lib 't/lib';
use Test::Chalk::Grammar;
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::Boolean;

subtest 'Parser generates both alternatives for ambiguous "n+n*n"' => sub {
    # Create ambiguous grammar: E -> E + E | E * E | n
    # This grammar has NO precedence - both operators at same level
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E' => [qw(E + E)] ],
            [ 'E' => [qw(E * E)] ],
            [ 'E' => ['n'] ],
        ]
    );

    # Use SPPF semiring to capture ALL parse alternatives
    my $sppf = Chalk::Semiring::SPPF->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf
    );

    my $result = $parser->parse_string('n+n*n');
    ok $result, 'Expression parses successfully';

    SKIP: {
        skip 'Parse failed' unless $result;

        my $forest = $sppf->forest;
        ok $forest, 'SPPF forest exists';

        # Find the root E node spanning entire input [0,5]
        my $root_node;
        for my $node (values %{$forest->nodes}) {
            if ($node->symbol eq 'E' && $node->start_pos == 0 && $node->end_pos == 5) {
                $root_node = $node;
                last;
            }
        }

        ok $root_node, 'Found root E node at [0,5]';

        SKIP: {
            skip 'No root node found' unless $root_node;

            my @packed = $root_node->packed_nodes;
            my $num_alternatives = scalar(@packed);

            note("Root E[0,5] has $num_alternatives packed alternative(s)");

            # For each alternative, identify the top-level operator
            for my $i (0..$#packed) {
                my $packed = $packed[$i];
                my $rule = $packed->rule;

                if ($rule) {
                    my $rhs = $rule->rhs;
                    my @ops = grep { defined($_) && !ref($_) && $_ =~ /^[+*]$/ } @$rhs;
                    my $op = $ops[0] // 'unknown';
                    note("  Alternative $i: top-level operator = '$op'");
                }
            }

            # EXPECTED: 2 alternatives
            #   Alternative 0: n + (n*n) - top operator '+'
            #   Alternative 1: (n+n) * n - top operator '*'
            # TODO: Parser not generating both parse alternatives - Bug being investigated
            todo 'Parser not generating both parse alternatives - Bug being investigated' => sub {
                is $num_alternatives, 2,
                    'Parser should generate 2 packed alternatives for ambiguous "n+n*n"';
            };
        }
    }
};

subtest 'Parser generates alternatives for longer ambiguous expression' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E' => [qw(E + E)] ],
            [ 'E' => [qw(E * E)] ],
            [ 'E' => ['n'] ],
        ]
    );

    my $sppf = Chalk::Semiring::SPPF->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf
    );

    # "n+n*n+n" has even more ambiguity
    my $result = $parser->parse_string('n+n*n+n');
    ok $result, 'Longer expression parses';

    SKIP: {
        skip 'Parse failed' unless $result;

        my $forest = $sppf->forest;

        # Find root E node at [0,7]
        my $root_node;
        for my $node (values %{$forest->nodes}) {
            if ($node->symbol eq 'E' && $node->start_pos == 0 && $node->end_pos == 7) {
                $root_node = $node;
                last;
            }
        }

        ok $root_node, 'Found root E node for longer expression';

        SKIP: {
            skip 'No root node found' unless $root_node;

            my @packed = $root_node->packed_nodes;
            my $num_alternatives = scalar(@packed);

            note("Root E[0,7] has $num_alternatives packed alternative(s)");

            # With exponentially ambiguous grammar, expect multiple alternatives
            # Exact number depends on grammar but should be > 1
            # TODO: Parser not generating multiple alternatives
            todo 'Parser not generating multiple alternatives' => sub {
                cmp_ok $num_alternatives, '>', 1,
                    'Longer ambiguous expression should have multiple alternatives';
            };
        }
    }
};

subtest 'Verify SPPF intermediate nodes for "n+n*n"' => sub {
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E' => [qw(E + E)] ],
            [ 'E' => [qw(E * E)] ],
            [ 'E' => ['n'] ],
        ]
    );

    my $sppf = Chalk::Semiring::SPPF->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf
    );

    my $result = $parser->parse_string('n+n*n');
    ok $result, 'Parse for SPPF structure verification';

    SKIP: {
        skip 'Parse failed' unless $result;

        my $forest = $sppf->forest;
        my @all_nodes = values %{$forest->nodes};

        # Should have E nodes at various positions
        my @e_nodes = grep { $_->symbol eq 'E' } @all_nodes;

        note("Found " . scalar(@e_nodes) . " E nodes in forest:");
        for my $node (@e_nodes) {
            my $span = sprintf("[%d,%d]", $node->start_pos, $node->end_pos);
            my $alts = scalar($node->packed_nodes);
            note("  E$span with $alts alternative(s)");
        }

        # At minimum, we expect:
        # E[0,1], E[2,3], E[4,5] - the leaf 'n' nodes
        # E[0,5] - the root
        # E[0,3] or E[2,5] - intermediate for one of the parses
        cmp_ok scalar(@e_nodes), '>=', 4,
            'Should have at least 4 E nodes (3 leaves + root)';

        # Check for intermediate nodes that would indicate both parses
        my @intermediate = grep {
            $_->start_pos == 0 && $_->end_pos == 3  # n+n
            || $_->start_pos == 2 && $_->end_pos == 5  # n*n
        } @e_nodes;

        # TODO: Parser may not be generating both intermediate structures
        todo 'Parser may not be generating both intermediate structures' => sub {
            cmp_ok scalar(@intermediate), '>=', 2,
                'Should have intermediate nodes for both n+n and n*n';
        };
    }
};

subtest 'Boolean semiring confirms parse succeeds but does not show alternatives' => sub {
    # This is a control test - Boolean semiring just says "yes it parses"
    # but doesn't preserve alternatives
    my $grammar = Test::Chalk::Grammar->build_grammar(
        rules => [
            [ 'E' => [qw(E + E)] ],
            [ 'E' => [qw(E * E)] ],
            [ 'E' => ['n'] ],
        ]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => Chalk::Semiring::Boolean->new()
    );

    my $result = $parser->parse_string('n+n*n');
    ok $result, 'Boolean semiring confirms parse succeeds';
    isa_ok $result, 'Chalk::Semiring::BooleanElement';

    # Boolean doesn't show us alternatives - that's expected
    # This test just confirms the grammar itself is valid
};
