#!/usr/bin/env perl
# ABOUTME: End-to-end tests for function call support
# ABOUTME: Part of issue #133 - Function Call Support (Chapter 18)

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
use Chalk::Interpreter::CEKDataflow;

# Helper to parse and execute Chalk code
sub run_chalk($code) {
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

    my $result = $parser->parse_string($code);
    return undef unless $result;

    # Get winning node
    my $winning_node;
    if ($result->can('context')) {
        my $ctx = $result->context;
        if ($ctx->can('focus')) {
            $winning_node = $ctx->focus;
        }
    }
    return undef unless $winning_node && blessed($winning_node) && $winning_node->can('id');

    # Build graph
    my $graph = Chalk::IR::Graph->new();
    my %visited;
    my @queue = ($winning_node);

    while (@queue) {
        my $node = shift @queue;
        next unless blessed($node) && $node->can('id');
        my $node_id = $node->id;
        next if $visited{$node_id}++;

        $graph->add_node($node);

        # Traverse node references
        for my $method (qw(value_node value control left right operand condition source call callee)) {
            next unless $node->can($method);
            my $ref = $node->$method;
            next unless blessed($ref) && $ref->can('id') && !$visited{$ref->id};
            push @queue, $ref;
        }

        # Handle arrays
        for my $method (qw(branches control_users args)) {
            next unless $node->can($method) && $node->$method;
            for my $ref ($node->$method->@*) {
                next unless blessed($ref) && $ref->can('id') && !$visited{$ref->id};
                push @queue, $ref;
            }
        }
    }

    # NOTE: Skipping GVN optimizer for function call tests
    # GVN has a known issue where it creates new nodes but doesn't update
    # input references in Call nodes. This is a separate bug to fix.
    # TODO: Issue for GVN input reference update

    # Execute with function registry
    my $func_registry = $semiring->function_registry;
    my $cek = Chalk::Interpreter::CEKDataflow->new(
        graph => $graph,
        function_registry => $func_registry,
    );

    return $cek->execute();
}

subtest 'Simple function returning constant' => sub {
    my $code = 'sub foo() { return 42; } return foo();';
    my $result = run_chalk($code);

    is $result, 42, 'Function returns correct value';
};

subtest 'Function with no parameters' => sub {
    my $code = 'sub greet() { return 1; } return greet();';
    my $result = run_chalk($code);

    is $result, 1, 'Function returns 1';
};

subtest 'Multiple function definitions' => sub {
    my $code = 'sub foo() { return 1; } sub bar() { return 2; } return 0;';
    my $result = run_chalk($code);

    is $result, 0, 'Program returns 0 (not calling functions)';
};

subtest 'Function registry is populated' => sub {
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

    my $code = 'sub alpha() { return 1; } sub beta($x) { return 2; } return 0;';
    my $result = $parser->parse_string($code);

    ok $result, 'Parse succeeded';

    my $registry = $semiring->function_registry;
    ok $registry->has('alpha'), 'alpha is registered';
    ok $registry->has('beta'), 'beta is registered';

    my $alpha = $registry->lookup('alpha');
    is $alpha->name, 'alpha', 'alpha has correct name';
    is $alpha->parameters, [], 'alpha has no parameters';

    my $beta = $registry->lookup('beta');
    is $beta->name, 'beta', 'beta has correct name';
};
