#!/usr/bin/env perl
# ABOUTME: Tests parsing of use overload statements and extraction of operator-to-method mappings
# ABOUTME: Ensures grammar rules and semantic actions correctly handle overload directives

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
use Chalk::Parser;
use Chalk::Semiring::Boolean;
use Chalk::Semiring::Semantic;
use Chalk::EvalContext;

# Load chalk.bnf grammar
my $bnf_file = File::Spec->catfile($RealBin, '../../grammar', 'chalk.bnf');
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');
my $semiring = Chalk::Semiring::Boolean->new();

sub parses_ok {
    my ($code, $name) = @_;
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );
    my $result = $parser->parse_string($code);
    ok($result, $name) or diag("Failed to parse: $code");
}

# Test 1: Basic use overload with single operator
parses_ok(q{
    use overload '""' => 'value';
}, 'basic use overload with stringification');

# Test 2: use overload with multiple operators
parses_ok(q{
    use overload
        '""'  => 'value',
        'eq'  => '_string_eq',
        'ne'  => '_string_ne',
        'cmp' => '_string_cmp';
}, 'use overload with multiple operators');

# Test 3: use overload with fallback
parses_ok(q{
    use overload
        '+'  => 'add',
        fallback => 1;
}, 'use overload with fallback');

# Test 4: use overload in class context
parses_ok(q{
    class Token {
        field $value :param;

        method value() { return $value; }
        method _string_eq($other) { return $value eq $other; }

        use overload
            '""'  => 'value',
            'eq'  => '_string_eq';
    }
}, 'use overload in class context');

# ============================================================================
# Semantic Extraction Tests - Verify operator-to-method mappings are extracted
# ============================================================================

sub extract_overload_from_ir {
    my ($ir) = @_;

    # Find UseStatement nodes with type='overload_directive'
    my @overload_nodes;

    # Traverse IR tree to find UseStatement nodes
    my @queue = ($ir);
    while (@queue) {
        my $node = shift @queue;
        next unless ref($node) && $node->can('op');

        if ($node->op eq 'UseStatement') {
            my $attrs = $node->attributes;
            if ($attrs && $attrs->{type} eq 'overload_directive') {
                push @overload_nodes, $node;
            }
        }

        # Add inputs to queue
        if ($node->can('inputs')) {
            push @queue, $node->inputs->@*;
        }
    }

    return \@overload_nodes;
}

# Test 5: Verify basic overload mapping extraction
{
    my $code = q{
        use overload '""' => 'value';
    };

    my $semantic_semiring = Chalk::Semiring::Semantic->new(
        env => { grammar_name => 'Chalk' },
        grammar => $grammar
    );
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semantic_semiring
    );

    my $ir = $parser->parse_string($code);
    ok($ir, 'IR generated for basic overload');

    # Extract actual IR from SemanticElement
    my $actual_ir = $ir;
    if ($ir && $ir->can('value')) {
        $actual_ir = $ir->value;
    }


    my $overload_nodes = extract_overload_from_ir($actual_ir);

    todo 'Full semantic verification will be tested in Phase 2 (IR Integration)' => sub {
        is(scalar(@$overload_nodes), 1, 'Found one overload directive');

        if (@$overload_nodes) {
            my $attrs = $overload_nodes->[0]->attributes;
            is($attrs->{type}, 'overload_directive', 'Type is overload_directive');
            is_deeply($attrs->{mappings}, {'""' => 'value'}, 'Mappings extracted correctly');
            is($attrs->{fallback}, 0, 'No fallback by default');
        }
    };
}

# Test 6: Verify multiple operator mappings
{
    my $code = q{
        use overload
            '""'  => 'value',
            'eq'  => '_string_eq',
            'cmp' => '_string_cmp';
    };

    my $semantic_semiring = Chalk::Semiring::Semantic->new(
        env => { grammar_name => 'Chalk' },
        grammar => $grammar
    );
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semantic_semiring
    );

    my $ir = $parser->parse_string($code);
    ok($ir, 'IR generated for multiple operators');

    # Extract actual IR from SemanticElement
    my $actual_ir = $ir;
    if ($ir && $ir->can('value')) {
        $actual_ir = $ir->value;
    }

    my $overload_nodes = extract_overload_from_ir($actual_ir);

    todo 'Full semantic verification will be tested in Phase 2 (IR Integration)' => sub {
        is(scalar(@$overload_nodes), 1, 'Found one overload directive');

        if (@$overload_nodes) {
            my $attrs = $overload_nodes->[0]->attributes;
            my $expected = {
                '""'  => 'value',
                'eq'  => '_string_eq',
                'cmp' => '_string_cmp',
            };
            is_deeply($attrs->{mappings}, $expected, 'Multiple mappings extracted');
        }
    };
}

# Test 7: Verify fallback extraction
{
    my $code = q{
        use overload
            '+'  => 'add',
            fallback => 1;
    };

    my $semantic_semiring = Chalk::Semiring::Semantic->new(
        env => { grammar_name => 'Chalk' },
        grammar => $grammar
    );
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semantic_semiring
    );

    my $ir = $parser->parse_string($code);
    ok($ir, 'IR generated for overload with fallback');

    # Extract actual IR from SemanticElement
    my $actual_ir = $ir;
    if ($ir && $ir->can('value')) {
        $actual_ir = $ir->value;
    }

    my $overload_nodes = extract_overload_from_ir($actual_ir);

    todo 'Full semantic verification will be tested in Phase 2 (IR Integration)' => sub {
        is(scalar(@$overload_nodes), 1, 'Found one overload directive');

        if (@$overload_nodes) {
            my $attrs = $overload_nodes->[0]->attributes;
            is_deeply($attrs->{mappings}, {'+' => 'add'}, 'Operator mapping extracted');
            is($attrs->{fallback}, 1, 'Fallback flag set');
        }
    };
}
