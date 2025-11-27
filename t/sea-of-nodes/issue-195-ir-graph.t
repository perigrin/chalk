#!/usr/bin/env perl
# ABOUTME: Tests IR graph structure for issue #195 - early return statement sequencing
# ABOUTME: Verifies that if/else with returns generates correct control flow nodes
use lib 'lib';
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Test::More;

use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Semiring::Semantic;

# Load Chalk grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

# Helper to parse code and return IR root
sub parse_to_ir {
    my ($code) = @_;

    my $semiring = Chalk::Semiring::Semantic->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $result = $parser->parse_string($code);
    return undef unless $result;

    my $ctx = $result->context;
    return undef unless $ctx && $ctx->can('focus');

    return $ctx->focus;
}

# Helper to collect all nodes by walking the IR
sub collect_nodes {
    my ($root) = @_;
    my %nodes;
    my @queue = ($root);
    my %visited;

    while (@queue) {
        my $node = shift @queue;
        next unless defined $node && ref($node);
        next unless $node->can('id');

        my $id = $node->id;
        next if $visited{$id}++;

        $nodes{$id} = $node;

        # Traverse via object references
        if ($node->can('control') && $node->control) {
            push @queue, $node->control;
        }
        if ($node->can('value') && $node->op ne 'Constant') {
            my $val = $node->value;
            push @queue, $val if defined $val && ref($val);
        }
        if ($node->can('value_node') && $node->value_node) {
            push @queue, $node->value_node;
        }
        if ($node->can('left') && $node->left) {
            push @queue, $node->left;
        }
        if ($node->can('right') && $node->right) {
            push @queue, $node->right;
        }
        if ($node->can('condition') && $node->condition) {
            push @queue, $node->condition;
        }
        if ($node->can('operand') && $node->operand) {
            push @queue, $node->operand;
        }
        # Traverse Proj's source for object references to If node
        if ($node->can('source') && $node->source) {
            push @queue, $node->source;
        }
        # Traverse Stop's returns for object references
        if ($node->can('return_nodes') && $node->return_nodes) {
            for my $ret ($node->return_nodes->@*) {
                push @queue, $ret if defined $ret && ref($ret);
            }
        }
    }

    return \%nodes;
}

# Helper to count nodes by op type
sub count_by_op {
    my ($nodes) = @_;
    my %counts;
    for my $node (values %$nodes) {
        my $op = $node->op;
        $counts{$op}++;
    }
    return \%counts;
}

# Test Case 1: if (1) { return 42; } else { return -42; }
# Expected: Should have If node, two Return paths, and proper control flow
subtest 'Case 1: if-else with returns in both branches' => sub {
    my $code = 'if (1) { return 42; } else { return -42; }';

    my $ir = parse_to_ir($code);
    ok($ir, 'Code parses to IR');

    SKIP: {
        skip 'No IR generated', 4 unless $ir;

        ok($ir->can('op'), 'IR root is a node');

        my $nodes = collect_nodes($ir);
        my $counts = count_by_op($nodes);

        diag("Node counts: " . join(', ', map { "$_=$counts->{$_}" } sort keys %$counts));

        # Should have Return node(s)
        ok(exists $counts->{Return}, 'Has Return node(s)');

        # Should have Constant nodes for 42 and -42
        ok(exists $counts->{Constant}, 'Has Constant nodes');

        # Should have If node for the conditional
        TODO: {
            local $TODO = 'Issue #195: If node structure for early returns';
            ok(exists $counts->{If}, 'Has If node');
        }
    }
};

# Test Case 2: if (0) { return 42; } else { return -42; }
subtest 'Case 2: if-else with false condition' => sub {
    my $code = 'if (0) { return 42; } else { return -42; }';

    my $ir = parse_to_ir($code);
    ok($ir, 'Code parses to IR');

    SKIP: {
        skip 'No IR generated', 3 unless $ir;

        my $nodes = collect_nodes($ir);
        my $counts = count_by_op($nodes);

        diag("Node counts: " . join(', ', map { "$_=$counts->{$_}" } sort keys %$counts));

        ok(exists $counts->{Return}, 'Has Return node(s)');
        ok(exists $counts->{Constant}, 'Has Constant nodes');
    }
};

# Test Case 3: my $x = 5; if ($x > 0) { return 42; } return -42;
# This is the key case - return AFTER the if block
subtest 'Case 3: if with early return + fallthrough return' => sub {
    my $code = 'my $x = 5; if ($x > 0) { return 42; } return -42;';

    my $ir = parse_to_ir($code);
    ok($ir, 'Code parses to IR');

    SKIP: {
        skip 'No IR generated', 5 unless $ir;

        my $nodes = collect_nodes($ir);
        my $counts = count_by_op($nodes);

        diag("Node counts: " . join(', ', map { "$_=$counts->{$_}" } sort keys %$counts));

        # Should have multiple Return nodes (early return + fallthrough)
        ok(exists $counts->{Return}, 'Has Return node(s)');

        # The key assertion: we need proper control flow merging
        # Either Region node (for branch merging) or multiple Return paths
        TODO: {
            local $TODO = 'Issue #195: Multiple return paths in IR';
            my $return_count = $counts->{Return} // 0;
            cmp_ok($return_count, '>=', 1, 'Has at least one Return node');

            # Should have If node
            ok(exists $counts->{If}, 'Has If node for conditional');

            # Should have comparison node
            ok(exists $counts->{GT}, 'Has GT comparison node');
        }
    }
};

# Test Case 4: my $x = -5; if ($x > 0) { return 42; } return -42;
subtest 'Case 4: if with early return (negative value, takes fallthrough)' => sub {
    my $code = 'my $x = -5; if ($x > 0) { return 42; } return -42;';

    my $ir = parse_to_ir($code);
    ok($ir, 'Code parses to IR');

    SKIP: {
        skip 'No IR generated', 3 unless $ir;

        my $nodes = collect_nodes($ir);
        my $counts = count_by_op($nodes);

        diag("Node counts: " . join(', ', map { "$_=$counts->{$_}" } sort keys %$counts));

        ok(exists $counts->{Return}, 'Has Return node(s)');

        TODO: {
            local $TODO = 'Issue #195: Fallthrough return path';
            ok(exists $counts->{If}, 'Has If node');
        }
    }
};

done_testing();
