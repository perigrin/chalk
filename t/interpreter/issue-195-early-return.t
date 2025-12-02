#!/usr/bin/env perl
# ABOUTME: Tests CEK interpreter execution for issue #195 - early return statement sequencing
# ABOUTME: Verifies correct return values for if/else with early returns
use lib 'lib';
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Test::More;
use Scalar::Util qw(blessed);

use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Semiring::ChalkIR;
use Chalk::IR::Graph;
use Chalk::IR::Optimizer::GVN;
use Chalk::Interpreter::CEKDataflow;

# Load Chalk grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

# Helper to parse, build graph, optimize, and execute code
# Returns (result, error) - result is undef on error
sub execute_chalk {
    my ($code) = @_;

    # Parse with ChalkIR semiring (generates IR during parsing)
    my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring,
        preprocess => ['Chalk::Preprocessor::Heredoc']
    );

    my $result = $parser->parse_string($code);
    return (undef, 'Parse failed') unless $result;

    # Extract winning IR node from parse result
    my $winning_node;
    if ($result->can('context')) {
        my $ctx = $result->context;
        if ($ctx->can('focus')) {
            $winning_node = $ctx->focus;
        }
    }

    return (undef, 'No IR node in parse result') unless $winning_node;
    return (undef, 'IR node not a node object') unless blessed($winning_node) && $winning_node->can('id');

    # Build graph by traversing from winning node
    my $graph = Chalk::IR::Graph->new();
    my %visited;
    my @queue = ($winning_node);

    while (@queue) {
        my $node = shift @queue;
        next unless blessed($node) && $node->can('id');
        my $node_id = $node->id;
        next if $visited{$node_id}++;

        $graph->add_node($node);

        # Traverse via object references
        if ($node->can('value_node')) {
            my $val = $node->value_node;
            push @queue, $val if blessed($val) && $val->can('id') && !$visited{$val->id};
        }
        if ($node->can('value') && $node->can('op') && $node->op ne 'Constant') {
            my $val = $node->value;
            push @queue, $val if blessed($val) && $val->can('id') && !$visited{$val->id};
        }
        if ($node->can('control') && $node->control) {
            my $ctrl = $node->control;
            push @queue, $ctrl if blessed($ctrl) && $ctrl->can('id') && !$visited{$ctrl->id};
        }
        if ($node->can('left')) {
            my $left = $node->left;
            push @queue, $left if blessed($left) && $left->can('id') && !$visited{$left->id};
        }
        if ($node->can('right')) {
            my $right = $node->right;
            push @queue, $right if blessed($right) && $right->can('id') && !$visited{$right->id};
        }
        if ($node->can('operand')) {
            my $op = $node->operand;
            push @queue, $op if blessed($op) && $op->can('id') && !$visited{$op->id};
        }
        if ($node->can('condition')) {
            my $cond = $node->condition;
            push @queue, $cond if blessed($cond) && $cond->can('id') && !$visited{$cond->id};
        }
        # Traverse Proj's source for object references to If node
        if ($node->can('source')) {
            my $src = $node->source;
            push @queue, $src if blessed($src) && $src->can('id') && !$visited{$src->id};
        }
        # Traverse Stop's returns for object references
        if ($node->can('return_nodes') && $node->return_nodes) {
            for my $ret ($node->return_nodes->@*) {
                push @queue, $ret if blessed($ret) && $ret->can('id') && !$visited{$ret->id};
            }
        }
    }


    # Run GVN optimizer
    my $gvn_result = Chalk::IR::Optimizer::GVN->run_gvn($graph);
    $graph = $gvn_result->{graph};

    # Execute with CEK interpreter
    my $cek = Chalk::Interpreter::CEKDataflow->new(graph => $graph);
    my $exec_result = eval { $cek->execute() };
    if ($@) {
        return (undef, "Execution error: $@");
    }

    return ($exec_result, undef);
}

# Test Case 1: if (1) { return 42; } else { return -42; }
# Expected: 42 (true branch taken)
subtest 'Case 1: if-else returns 42 when condition is true' => sub {
    my $code = 'if (1) { return 42; } else { return -42; }';

    my ($result, $error) = execute_chalk($code);

    if ($error) {
        diag("Error: $error");
    }

    ok(!$error, 'Execution succeeded');
    is($result, 42, 'Returns 42 for true condition');
};

# Test Case 2: if (0) { return 42; } else { return -42; }
# Expected: -42 (false branch taken)
subtest 'Case 2: if-else returns -42 when condition is false' => sub {
    my $code = 'if (0) { return 42; } else { return -42; }';

    my ($result, $error) = execute_chalk($code);

    if ($error) {
        diag("Error: $error");
    }

    ok(!$error, 'Execution succeeded');
    is($result, -42, 'Returns -42 for false condition');
};

# Test Case 3: my $x = 5; if ($x > 0) { return 42; } return -42;
# Expected: 42 (early return taken because 5 > 0)
subtest 'Case 3: early return when condition true' => sub {
    my $code = 'my $x = 5; if ($x > 0) { return 42; } return -42;';

    my ($result, $error) = execute_chalk($code);

    if ($error) {
        diag("Error: $error");
    }

    ok(!$error, 'Execution succeeded');
    is($result, 42, 'Returns 42 via early return (5 > 0)');
};

# Test Case 4: my $x = -5; if ($x > 0) { return 42; } return -42;
# Expected: -42 (fallthrough return because -5 > 0 is false)
subtest 'Case 4: fallthrough return when condition false' => sub {
    my $code = 'my $x = -5; if ($x > 0) { return 42; } return -42;';

    my ($result, $error) = execute_chalk($code);

    if ($error) {
        diag("Error: $error");
    }

    ok(!$error, 'Execution succeeded');
    is($result, -42, 'Returns -42 via fallthrough (-5 > 0 is false)');
};

# Baseline test: simple return (should work)
subtest 'Baseline: simple return works' => sub {
    my $code = 'return 100;';

    my ($result, $error) = execute_chalk($code);

    if ($error) {
        diag("Error: $error");
    }

    ok(!$error, 'Simple return execution succeeded');
    is($result, 100, 'Returns 100');
};

# NOTE: These tests are failing due to a separate issue with graph traversal
# after the pending_nodes refactoring in commit 2f5718ad. The Return nodes
# are not being found in the graph. This is tracked separately from issue #132.

done_testing();
