#!/usr/bin/env perl
# ABOUTME: Tests for GVN optimizer input reference updates
# ABOUTME: Issue #443 - GVN doesn't update input references when replacing nodes

use lib 'lib';
use 5.42.0;
use Test2::V0;
use experimental qw(defer);
defer { done_testing() }

use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;
use Chalk::IR::Graph;
use Chalk::IR::Optimizer::GVN;

subtest 'GVN maintains input reference integrity' => sub {
    my $bnf_file = "grammar/chalk.bnf";
    open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');
    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
    );

    # Parse code with a function call
    my $code = 'sub foo() { return 42; } return foo();';
    my $result = $parser->parse_string($code);

    ok $result, 'Parse succeeded';

    # Get winning node and build graph
    my $winning_node;
    if ($result->can('context')) {
        my $ctx = $result->context;
        if ($ctx->can('focus')) {
            $winning_node = $ctx->focus;
        }
    }

    my $graph = Chalk::IR::Graph->new();
    my %visited;
    my @queue = ($winning_node);

    while (@queue) {
        my $node = shift @queue;
        next unless blessed($node) && $node->can('id');
        my $node_id = $node->id;
        next if $visited{$node_id}++;

        $graph->add_node($node);

        for my $method (qw(value_node value control left right operand condition source call callee)) {
            next unless $node->can($method);
            my $ref = $node->$method;
            next unless blessed($ref) && $ref->can('id') && !$visited{$ref->id};
            push @queue, $ref;
        }
    }

    # Verify all inputs are valid BEFORE GVN
    my $all_valid_before = 1;
    for my $id (keys $graph->nodes->%*) {
        my $node = $graph->nodes->{$id};
        for my $input_id ($node->inputs->@*) {
            unless (exists $graph->nodes->{$input_id}) {
                $all_valid_before = 0;
                last;
            }
        }
    }
    ok $all_valid_before, 'All input references valid before GVN';

    # Run GVN
    my $gvn_result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    $graph = $gvn_result->{graph};

    # TODO: Issue #443 - GVN should update input references when replacing nodes
    # Currently this fails because Call.inputs references the old Constant node ID
    my $all_valid_after = 1;
    my @broken_refs;
    for my $id (keys $graph->nodes->%*) {
        my $node = $graph->nodes->{$id};
        for my $input_id ($node->inputs->@*) {
            unless (exists $graph->nodes->{$input_id}) {
                $all_valid_after = 0;
                push @broken_refs, { node => $node->op, missing_input => $input_id };
            }
        }
    }

    todo 'Issue #443: GVN should update input references when replacing nodes' => sub {
        ok $all_valid_after, 'All input references valid after GVN';
        is scalar(@broken_refs), 0, 'No broken references after GVN';
    };
};
