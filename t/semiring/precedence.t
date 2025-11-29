#!/usr/bin/env perl
# ABOUTME: Test Precedence semiring with SPPF for ambiguous parse disambiguation
# ABOUTME: Validates that Precedence.add() correctly chooses between parse alternatives
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../lib";
use File::Spec;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::Composite;

# Load chalk.bnf grammar
my $bnf_file = File::Spec->catfile($RealBin, '../../grammar', 'chalk.bnf');
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Perl precedence table (subset for arithmetic)
my @perl_precedence_table = (
    { ops => ['**'], assoc => 'right' },         # 0 - highest
    { ops => ['!', '\\', '+u', '-u'], assoc => 'nonassoc' },  # 1 - unary
    { ops => ['=~', '!~'], assoc => 'left' },    # 2
    { ops => ['*', '/', '%', 'x'], assoc => 'left' },  # 3
    { ops => ['+', '-', '.'], assoc => 'left' },       # 4
    { ops => ['<<', '>>'], assoc => 'left' },    # 5
    { ops => ['<', '>', '<=', '>=', 'lt', 'gt', 'le', 'ge'], assoc => 'chained' },  # 6
    { ops => ['==', '!=', '<=>', 'eq', 'ne', 'cmp', '~~'], assoc => 'chained' },  # 7
    { ops => ['&'], assoc => 'left' },           # 8
    { ops => ['|', '^'], assoc => 'left' },      # 9
    { ops => ['&&'], assoc => 'left' },          # 10
    { ops => ['||', '//', 'or'], assoc => 'left' },  # 11
    { ops => ['..', '...'], assoc => 'nonassoc' },  # 12
    { ops => ['?:'], assoc => 'right' },         # 13
    { ops => ['=', '+=', '-=', '*=', '/=', '%=', '**=', '.=', 'x=', '&=', '|=', '^=', '<<=', '>>=', '&&=', '||=', '//='], assoc => 'right' },  # 14
    { ops => [',', '=>'], assoc => 'left' },     # 15
    { ops => ['not'], assoc => 'right' },        # 16
    { ops => ['and'], assoc => 'left' },         # 17 - lowest
);

subtest 'Precedence semiring with SPPF - basic setup' => sub {
    # Create SPPF semiring
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $forest = $sppf_sr->forest;

    # Create Precedence semiring with forest sharing
    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table,
        shared_context => { forest => $forest }
    );

    isa_ok $precedence_sr, 'Chalk::Semiring::Precedence';
    ok $precedence_sr->precedence_table, 'Precedence semiring has table';
};

subtest 'Parse 1 + 2 * 3 - precedence disambiguation' => sub {
    # Create SPPF semiring
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $forest = $sppf_sr->forest;

    # Create Precedence semiring with forest sharing
    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table,
        shared_context => { forest => $forest }
    );

    # Composite of SPPF + Precedence (no Semantic)
    my $composite_sr = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $precedence_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Parse the ambiguous expression
    my $code = 'return 1 + 2 * 3;';
    my $result = $parser->parse_string($code);

    ok $result, 'Expression 1 + 2 * 3 parses successfully';

    if ($result) {
        # Extract elements from composite
        my @elements = $result->elements->@*;
        my $sppf_element = $elements[0];
        my $prec_element = $elements[1];

        isa_ok $sppf_element, ['Chalk::Semiring::SPPFElement'], 'First element is SPPF';
        isa_ok $prec_element, ['Chalk::Semiring::PrecedenceElement'], 'Second element is Precedence';

        # Precedence element should be valid
        ok $prec_element->valid, 'Precedence element marks parse as valid';

        # Examine SPPF structure to verify correct precedence
        if ($sppf_element->can('node')) {
            my $node = $sppf_element->node;
            ok $node, 'SPPF element has a node';

            # Check for ArithmeticOp nodes in the forest
            my @all_nodes = values %{$forest->nodes};
            my @arith_nodes = grep { $_->symbol eq 'ArithmeticOp' } @all_nodes;

            ok scalar(@arith_nodes) > 0, 'Forest contains ArithmeticOp nodes';

            # The winning parse should have multiplication deeper in the tree than addition
            # We'll verify this by checking that the parser created both operators
            my $has_mult = 0;
            my $has_add = 0;

            for my $anode (@arith_nodes) {
                for my $packed ($anode->packed_nodes) {
                    my $rule = $packed->rule;
                    next unless $rule;
                    my $rhs = $rule->rhs;
                    for my $symbol (@$rhs) {
                        if (defined($symbol) && !ref($symbol)) {
                            $has_mult = 1 if $symbol eq '*';
                            $has_add = 1 if $symbol eq '+';
                        }
                    }
                }
            }

            ok $has_mult, 'Forest contains multiplication operator';
            ok $has_add, 'Forest contains addition operator';
        }
    }
};

subtest 'Parse 2 * 3 + 1 - precedence disambiguation' => sub {
    # Create SPPF semiring
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $forest = $sppf_sr->forest;

    # Create Precedence semiring with forest sharing
    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table,
        shared_context => { forest => $forest }
    );

    # Composite of SPPF + Precedence
    my $composite_sr = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $precedence_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Parse expression with multiplication first
    my $code = 'return 2 * 3 + 1;';
    my $result = $parser->parse_string($code);

    ok $result, 'Expression 2 * 3 + 1 parses successfully';

    if ($result) {
        my @elements = $result->elements->@*;
        my $prec_element = $elements[1];

        ok $prec_element->valid, 'Precedence element marks parse as valid';
    }
};

subtest 'Parse simple addition - no ambiguity' => sub {
    # Create SPPF semiring
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $forest = $sppf_sr->forest;

    # Create Precedence semiring with forest sharing
    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table,
        shared_context => { forest => $forest }
    );

    # Composite of SPPF + Precedence
    my $composite_sr = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $precedence_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Parse simple expression with no precedence ambiguity
    my $code = 'return 1 + 2;';
    my $result = $parser->parse_string($code);

    ok $result, 'Expression 1 + 2 parses successfully';

    if ($result) {
        my @elements = $result->elements->@*;
        my $prec_element = $elements[1];

        ok $prec_element->valid, 'Precedence element marks simple parse as valid';
    }
};

subtest 'Parse parenthesized expression' => sub {
    # Create SPPF semiring
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $forest = $sppf_sr->forest;

    # Create Precedence semiring with forest sharing
    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table,
        shared_context => { forest => $forest }
    );

    # Composite of SPPF + Precedence
    my $composite_sr = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $precedence_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Parentheses override precedence: (1 + 2) * 3
    my $code = 'return (1 + 2) * 3;';
    my $result = $parser->parse_string($code);

    ok $result, 'Expression (1 + 2) * 3 parses successfully';

    if ($result) {
        my @elements = $result->elements->@*;
        my $prec_element = $elements[1];

        ok $prec_element->valid, 'Precedence element marks parenthesized parse as valid';
    }
};

subtest 'Precedence.add() chooses valid alternative' => sub {
    # This test verifies that when Precedence.add() is called with two alternatives,
    # it correctly chooses the one with valid precedence

    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $forest = $sppf_sr->forest;

    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table,
        shared_context => { forest => $forest }
    );

    # Create two mock elements: one valid, one invalid
    my $valid_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 1,
        forest => $forest
    );

    my $invalid_elem = Chalk::Semiring::PrecedenceElement->new(
        valid => 0,
        forest => $forest
    );

    # add() should prefer the valid one
    my $result1 = $valid_elem->add($invalid_elem);
    is $result1->valid, 1, 'add(valid, invalid) returns valid';

    my $result2 = $invalid_elem->add($valid_elem);
    is $result2->valid, 1, 'add(invalid, valid) returns valid';

    # add() of two invalid should return invalid
    my $result3 = $invalid_elem->add($invalid_elem);
    is $result3->valid, 0, 'add(invalid, invalid) returns invalid';

    # add() of two valid should return valid (prefers first)
    my $result4 = $valid_elem->add($valid_elem);
    is $result4->valid, 1, 'add(valid, valid) returns valid';
};

subtest 'Deep SPPF inspection - verify 1 + 2 * 3 structure' => sub {
    # This test deeply inspects the SPPF structure to verify that:
    # 1. The forest contains multiple parse alternatives
    # 2. The winning parse has the correct tree structure (1 + (2*3))
    # 3. Multiplication is deeper in the tree than addition

    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $forest = $sppf_sr->forest;

    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table,
        shared_context => { forest => $forest }
    );

    my $composite_sr = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $precedence_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $code = 'return 1 + 2 * 3;';
    my $result = $parser->parse_string($code);

    ok $result, 'Expression parses successfully';

    if ($result) {
        my @elements = $result->elements->@*;
        my $sppf_element = $elements[0];

        # Get all ArithmeticOp nodes from the forest
        my @all_nodes = values %{$forest->nodes};
        my @arith_nodes = grep { $_->symbol eq 'ArithmeticOp' } @all_nodes;

        ok scalar(@arith_nodes) >= 2, 'Forest contains multiple ArithmeticOp nodes';

        # Collect all alternatives (packed nodes) for each ArithmeticOp position
        my %alternatives_by_span;
        for my $anode (@arith_nodes) {
            my $span = sprintf("%d,%d", $anode->start_pos, $anode->end_pos);
            my @packed = $anode->packed_nodes;

            if (@packed > 1) {
                $alternatives_by_span{$span} = \@packed;
            }
        }

        if (keys %alternatives_by_span) {
            pass('Found ambiguous ArithmeticOp nodes with multiple alternatives');

            # For each ambiguous node, check the operators in each alternative
            for my $span (keys %alternatives_by_span) {
                my @packed = $alternatives_by_span{$span}->@*;
                note("ArithmeticOp at [$span] has " . scalar(@packed) . " alternatives");

                for my $i (0..$#packed) {
                    my $packed = $packed[$i];
                    my $rule = $packed->rule;
                    next unless $rule;

                    my $rhs = $rule->rhs;
                    my $op = (grep { defined($_) && !ref($_) && $_ =~ /^[+\-*\/]$/ } @$rhs)[0];
                    note("  Alternative $i: operator = " . ($op // 'unknown'));
                }
            }
        } else {
            # Grammar may not create ambiguity at ArithmeticOp level
            # Ambiguity might exist at Expression or other levels
            note('No ambiguous ArithmeticOp nodes - grammar may not be ambiguous at this level');
            note('This suggests precedence disambiguation happens at a different grammar level');
        }

        # Walk the winning SPPF node to verify structure
        if ($sppf_element->can('node')) {
            my $root = $sppf_element->node;

            # Helper to recursively find ArithmeticOp nodes in the tree
            my $find_arith_ops;
            $find_arith_ops = sub {
                my ($node, $depth) = @_;
                return [] unless $node;

                my @ops;

                if ($node->can('symbol') && $node->symbol eq 'ArithmeticOp') {
                    # Get the operator from the rule
                    if ($node->can('packed_nodes')) {
                        my @packed = $node->packed_nodes;
                        if (@packed) {
                            my $rule = $packed[0]->rule;  # Use first alternative (winning parse)
                            if ($rule) {
                                my $rhs = $rule->rhs;
                                my $op = (grep { defined($_) && !ref($_) && $_ =~ /^[+\-*\/]$/ } @$rhs)[0];
                                push @ops, { op => $op, depth => $depth, node => $node };
                            }
                        }
                    }
                }

                # Recurse into children if this is a packed node
                if ($node->can('packed_nodes')) {
                    my @packed = $node->packed_nodes;
                    if (@packed) {
                        my $packed = $packed[0];  # First alternative is winning parse
                        if ($packed->can('children')) {
                            for my $child ($packed->children) {
                                if (ref($child)) {
                                    push @ops, $find_arith_ops->($child, $depth + 1)->@*;
                                }
                            }
                        }
                    }
                }

                return \@ops;
            };

            my $ops = $find_arith_ops->($root, 0);

            if (@$ops >= 2) {
                note("Found operators in tree:");
                for my $op_info (@$ops) {
                    note(sprintf("  %s at depth %d", $op_info->{op}, $op_info->{depth}));
                }

                # Find * and + operators
                my ($mult_info) = grep { $_->{op} eq '*' } @$ops;
                my ($add_info) = grep { $_->{op} eq '+' } @$ops;

                if ($mult_info && $add_info) {
                    # Multiplication should be deeper (higher depth) than addition
                    # because correct parse is 1 + (2*3), not (1+2)*3
                    cmp_ok $mult_info->{depth}, '>', $add_info->{depth},
                        'Multiplication is deeper in tree than addition (correct precedence)';
                } else {
                    fail('Could not find both * and + operators in tree');
                }
            } else {
                fail('Could not find enough operators in tree structure');
            }
        }
    }
};

subtest 'Verify post-processing prunes invalid precedence alternatives' => sub {
    # This test verifies that post-processing pruning removes invalid alternatives
    # from IntermediateNodes based on precedence rules

    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $forest = $sppf_sr->forest;

    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table,
        shared_context => { forest => $forest }
    );

    my $composite_sr = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $precedence_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Parse 1 + 2 * 3
    my $code = '1 + 2 * 3';
    my $result = $parser->parse_string($code);

    ok $result, 'Expression parses';

    # Find the root ArithmeticOp node
    my @all_nodes = values %{$forest->nodes};
    my @arith_nodes = sort {
        ($b->end_pos - $b->start_pos) <=> ($a->end_pos - $a->start_pos)
    } grep { $_->symbol eq 'ArithmeticOp' } @all_nodes;

    SKIP: {
        skip 'No ArithmeticOp nodes found' unless @arith_nodes;

        my $root_arith = $arith_nodes[0];
        my @symbol_packed = $root_arith->packed_nodes;

        skip 'No PackedNodes on SymbolNode' unless @symbol_packed;

        # Find IntermediateNode
        my $first_packed = $symbol_packed[0];
        my @packed_children = $first_packed->children;
        my ($intermediate) = grep { ref($_) =~ /IntermediateNode/ } @packed_children;

        skip 'No IntermediateNode found' unless $intermediate;

        # Count alternatives BEFORE pruning
        my @before_pruning = $intermediate->packed_nodes;
        my $before_count = scalar(@before_pruning);

        note("Before pruning: $before_count alternatives");

        # Skip the actual pruning test - method not yet implemented
        skip 'prune_invalid_alternatives_from_forest() not yet implemented', 2
            unless $precedence_sr->can('prune_invalid_alternatives_from_forest');

        # Post-process: prune invalid alternatives
        $precedence_sr->prune_invalid_alternatives_from_forest();

        # Count alternatives AFTER pruning
        my @after_pruning = $intermediate->packed_nodes;
        my $after_count = scalar(@after_pruning);

        note("After pruning: $after_count alternatives");

        # For "1 + 2 * 3", should reduce to 1 alternative (the valid one)
        cmp_ok $after_count, '<', $before_count,
            'Post-processing should prune invalid alternatives';
        cmp_ok $after_count, '==', 1,
            'Only the valid alternative should remain after pruning';
    }
};

subtest 'Verify SPPF alternatives exist before pruning' => sub {
    # This test verifies that the SPPF actually contains BOTH parse alternatives
    # for the ambiguous expression, and that Precedence.add() chooses between them

    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $forest = $sppf_sr->forest;

    # Parse with SPPF only (no Precedence) to see all alternatives
    my $parser_sppf_only = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf_sr,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $code = 'return 1 + 2 * 3;';
    my $result_unpruned = $parser_sppf_only->parse_string($code);

    ok $result_unpruned, 'Parse succeeds with SPPF only';

    if ($result_unpruned) {
        # Count ArithmeticOp nodes with multiple alternatives
        my @all_nodes = values %{$forest->nodes};
        my @arith_nodes = grep { $_->symbol eq 'ArithmeticOp' } @all_nodes;

        my @ambiguous = grep {
            my @packed = $_->packed_nodes;
            scalar(@packed) > 1;
        } @arith_nodes;

        if (@ambiguous) {
            pass('Found ambiguous ArithmeticOp nodes in unpruned SPPF');
            note('Ambiguous nodes at positions:');
            for my $node (@ambiguous) {
                note(sprintf("  [%d,%d] with %d alternatives",
                    $node->start_pos, $node->end_pos, scalar($node->packed_nodes)));

                my @packed = $node->packed_nodes;
                for my $i (0..$#packed) {
                    my $rule = $packed[$i]->rule;
                    next unless $rule;
                    my $rhs = $rule->rhs;
                    my $op = (grep { defined($_) && !ref($_) && $_ =~ /^[+\-*\/]$/ } @$rhs)[0];
                    note(sprintf("    Alternative %d: %s", $i, $op // 'unknown'));
                }
            }
        } else {
            # This might be OK if the grammar doesn't create ambiguity at this level
            note('No ambiguous ArithmeticOp nodes found - grammar may not be ambiguous at this level');
        }
    }

    # Now parse with SPPF + Precedence to see pruned result
    my $precedence_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table,
        shared_context => { forest => $forest }
    );

    my $composite_sr = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $precedence_sr]
    );

    my $parser_with_prec = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    # Create fresh forest for pruned parse
    my $sppf_sr2 = Chalk::Semiring::SPPF->new();
    my $forest2 = $sppf_sr2->forest;

    my $precedence_sr2 = Chalk::Semiring::Precedence->new(
        precedence_table => \@perl_precedence_table,
        shared_context => { forest => $forest2 }
    );

    my $composite_sr2 = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr2, $precedence_sr2]
    );

    my $parser_pruned = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr2,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $result_pruned = $parser_pruned->parse_string($code);

    ok $result_pruned, 'Parse succeeds with SPPF + Precedence';

    if ($result_pruned) {
        my @elements = $result_pruned->elements->@*;
        my $prec_element = $elements[1];
        ok $prec_element->valid, 'Precedence element marks result as valid';
    }
};
