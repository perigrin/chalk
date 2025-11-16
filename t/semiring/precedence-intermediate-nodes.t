#!/usr/bin/env perl
# ABOUTME: Test Precedence semiring traversing IntermediateNodes to find and prune invalid alternatives
# ABOUTME: Verifies precedence filtering works with Scott's SPPF binarized structure
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use File::Spec;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::SPPF;
use Chalk::Semiring::Composite;

# Load Chalk grammar
my $bnf_file = File::Spec->catfile($RealBin, '../../grammar', 'chalk.bnf');
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Perl precedence table
my @precedence_table = (
    { assoc => 'left',  ops => ['*', '/', '%'] },  # Index 0 - Higher precedence
    { assoc => 'left',  ops => ['+', '-'] },       # Index 1 - Lower precedence
);

subtest 'IntermediateNode contains multiple PackedNode alternatives' => sub {
    # First verify that SPPF alone (no precedence) creates IntermediateNodes with alternatives
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $sppf_sr
    );

    my $code = 'return 1 + 2 * 3;';
    my $result = $parser->parse_string($code);
    ok $result, 'Parse succeeds with SPPF only';

    SKIP: {
        skip 'Parse failed' unless $result;

        my $forest = $sppf_sr->forest;

        # Find ArithmeticOp[0,16] (or whatever the root span is)
        my @all_nodes = values %{$forest->nodes};
        my @arith_nodes = sort {
            ($b->end_pos - $b->start_pos) <=> ($a->end_pos - $a->start_pos)
        } grep { $_->symbol eq 'ArithmeticOp' } @all_nodes;

        ok scalar(@arith_nodes) > 0, 'Found ArithmeticOp nodes';

        SKIP: {
            skip 'No ArithmeticOp nodes found' unless @arith_nodes;

            my $root_arith = $arith_nodes[0];
            my $span = sprintf("[%d,%d]", $root_arith->start_pos, $root_arith->end_pos);

            my @symbol_packed = $root_arith->packed_nodes;
            is scalar(@symbol_packed), 1,
                "ArithmeticOp$span SymbolNode has 1 PackedNode (per Scott's algorithm)";

            SKIP: {
                skip 'No PackedNodes on SymbolNode' unless @symbol_packed;

                my $first_packed = $symbol_packed[0];
                my @packed_children = $first_packed->children;

                ok scalar(@packed_children) > 0, 'PackedNode has children';

                # Find IntermediateNode child
                my ($intermediate) = grep {
                    ref($_) =~ /IntermediateNode/
                } @packed_children;

                ok $intermediate, 'Found IntermediateNode child';

                SKIP: {
                    skip 'No IntermediateNode found' unless $intermediate;

                    my @int_packed = $intermediate->packed_nodes;
                    note("IntermediateNode has " . scalar(@int_packed) . " PackedNode alternatives");

                    # This is the key verification: IntermediateNode should have multiple alternatives
                    # representing different parse partitions
                    cmp_ok scalar(@int_packed), '>=', 2,
                        'IntermediateNode should have multiple PackedNode alternatives (both parse trees)';
                }
            }
        }
    }
};

subtest 'Precedence semiring prunes invalid alternatives from IntermediateNodes' => sub {
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $forest = $sppf_sr->forest;

    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table,
        shared_context => { forest => $forest }
    );

    my $composite_sr = Chalk::Semiring::Composite->new(
        semirings => [$sppf_sr, $prec_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite_sr
    );

    my $code = 'return 1 + 2 * 3;';
    my $result = $parser->parse_string($code);
    ok $result, 'Parse succeeds with Precedence filtering';

    # Post-process: prune invalid alternatives from SPPF after parsing completes
    $prec_sr->prune_invalid_alternatives_from_forest();

    SKIP: {
        skip 'Parse failed' unless $result;

        # Find root ArithmeticOp node
        my @all_nodes = values %{$forest->nodes};
        my @arith_nodes = sort {
            ($b->end_pos - $b->start_pos) <=> ($a->end_pos - $a->start_pos)
        } grep { $_->symbol eq 'ArithmeticOp' } @all_nodes;

        SKIP: {
            skip 'No ArithmeticOp nodes found' unless @arith_nodes;

            my $root_arith = $arith_nodes[0];
            my @symbol_packed = $root_arith->packed_nodes;

            SKIP: {
                skip 'No PackedNodes on SymbolNode' unless @symbol_packed;

                my $first_packed = $symbol_packed[0];
                my @packed_children = $first_packed->children;

                my ($intermediate) = grep {
                    ref($_) =~ /IntermediateNode/
                } @packed_children;

                SKIP: {
                    skip 'No IntermediateNode found' unless $intermediate;

                    my @int_packed = $intermediate->packed_nodes;

                    # After precedence filtering, invalid alternatives should be pruned
                    # For "1 + 2 * 3", the valid parse is "1 + (2*3)" (+ at top level)
                    # The invalid parse "(1+2) * 3" (* at top level) should be removed

                    note("After precedence filtering: " . scalar(@int_packed) . " PackedNode alternatives remain");

                    # Precedence filtering should remove invalid alternatives
                    # For "1 + 2 * 3", the valid parse is "1 + (2*3)" (+ at top level)
                    # The invalid parse "(1+2) * 3" (* at top level) should be removed
                    cmp_ok scalar(@int_packed), '==', 1,
                        'Invalid alternatives should be pruned from IntermediateNode';
                }
            }
        }
    }
};

subtest 'Precedence validation traverses IntermediateNodes to find operators' => sub {
    my $sppf_sr = Chalk::Semiring::SPPF->new();
    my $forest = $sppf_sr->forest;

    my $prec_sr = Chalk::Semiring::Precedence->new(
        precedence_table => \@precedence_table,
        shared_context => { forest => $forest }
    );

    # Monkey-patch to track validation calls
    my @validation_calls;
    {
        no warnings 'redefine';
        my $orig_validate = \&Chalk::Semiring::PrecedenceElement::_validate_element_precedence;
        local *Chalk::Semiring::PrecedenceElement::_validate_element_precedence = sub {
            my ($self) = @_;

            # Track that validation was called
            push @validation_calls, {
                has_sppf_node => defined($self->sppf_node),
                operator => $self->operator // 'undef',
            };

            return $orig_validate->($self);
        };

        my $composite_sr = Chalk::Semiring::Composite->new(
            semirings => [$sppf_sr, $prec_sr]
        );

        my $parser = Chalk::Parser->new(
            grammar => $grammar,
            semiring => $composite_sr
        );

        my $code = 'return 1 + 2 * 3;';
        $parser->parse_string($code);
    }

    ok scalar(@validation_calls) > 0, 'Validation was called';

    # The key test: validation should discover both operators by traversing IntermediateNodes
    my @with_plus = grep { $_->{operator} eq '+' } @validation_calls;
    my @with_mult = grep { $_->{operator} eq '*' } @validation_calls;

    note("Validation calls with '+': " . scalar(@with_plus));
    note("Validation calls with '*': " . scalar(@with_mult));

    todo 'Validation does not yet extract operators from IntermediateNodes' => sub {
        ok scalar(@with_plus) > 0,
            'Validation should find + operator by traversing IntermediateNodes';
        ok scalar(@with_mult) > 0,
            'Validation should find * operator by traversing IntermediateNodes';
    };
};
