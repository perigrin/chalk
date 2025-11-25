#!/usr/bin/env perl
# ABOUTME: Tests AST/SPPF structure for early return patterns in issue #195
# ABOUTME: Verifies parse tree has correct ConditionalStatement and ReturnStatement nodes

use 5.42.0;
use experimental qw(class);
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";

use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::ChalkSyntax;
use Chalk::Semiring::AST;
use Chalk::Semiring::Composite;

# Load Chalk grammar
open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Helper to parse and get AST
sub parse_code {
    my ($code) = @_;

    # Use ChalkSyntax + AST composite for parsing with validation
    my $chalksyntax = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
    my $ast = Chalk::Semiring::AST->new();
    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$chalksyntax, $ast]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $result = $parser->parse_string($code);
    return undef unless $result;

    # Extract AST element from composite (index 1)
    if ($result->can('elements')) {
        my @elements = $result->elements->@*;
        return $elements[1] if @elements > 1;
    }

    return $result;
}

# Helper to recursively dump AST structure
sub dump_ast {
    my ($node, $indent) = @_;
    $indent //= 0;
    my $prefix = "  " x $indent;

    return unless $node;

    if (blessed($node) && $node->can('rule_name')) {
        my $rule_name = $node->rule_name // 'NO_RULE';

        # Check if this is a terminal node
        if (defined($node->terminal)) {
            diag("${prefix}Terminal: " . $node->terminal);
            return;
        }

        diag("${prefix}Rule: $rule_name");

        # Recurse into children
        if ($node->can('children')) {
            my @children = $node->children->@*;
            for my $i (0..$#children) {
                my $child = $children[$i];
                next unless $child;
                dump_ast($child, $indent + 1);
            }
        }
    }
}

# Helper to count nodes of specific rule type
sub count_rule_nodes {
    my ($node, $rule_name) = @_;
    return 0 unless $node;

    my $count = 0;

    if (blessed($node) && $node->can('rule_name')) {
        my $node_rule = $node->rule_name;
        if (defined($node_rule) && $node_rule eq $rule_name) {
            $count++;
        }

        # Recurse into children
        if ($node->can('children')) {
            for my $child ($node->children->@*) {
                $count += count_rule_nodes($child, $rule_name);
            }
        }
    }

    return $count;
}

# Helper to find nodes of specific rule type
sub find_rule_nodes {
    my ($node, $rule_name) = @_;
    return () unless $node;

    my @found;

    if (blessed($node) && $node->can('rule_name')) {
        my $node_rule = $node->rule_name;
        if (defined($node_rule) && $node_rule eq $rule_name) {
            push @found, $node;
        }

        # Recurse into children
        if ($node->can('children')) {
            for my $child ($node->children->@*) {
                push @found, find_rule_nodes($child, $rule_name);
            }
        }
    }

    return @found;
}

subtest 'Simple early return in if (no else)' => sub {
    my $code = q{
my $x = 5;
if ($x > 0) {
    return 42;
}
return -42;
};

    my $result = parse_code($code);
    ok($result, 'Parse succeeded');

    SKIP: {
        skip "No parse result", 5 unless $result;

        # Check for expected rule nodes
        my $cond_count = count_rule_nodes($result, 'ConditionalStatement');
        my $ret_count = count_rule_nodes($result, 'ReturnStatement');

        diag("ConditionalStatement nodes: $cond_count");
        diag("ReturnStatement nodes: $ret_count");

        is($cond_count, 1, 'Should have 1 ConditionalStatement node');
        is($ret_count, 2, 'Should have 2 ReturnStatement nodes');

        # Dump the structure for debugging
        diag("\n=== AST Structure for early return (no else) ===");
        dump_ast($result);

        # Find the ConditionalStatement and verify it has no else
        my @conds = find_rule_nodes($result, 'ConditionalStatement');
        if (@conds) {
            my $cond_ast = $conds[0];
            my @children = $cond_ast->children->@*;

            # Look for 'else' terminal in children
            my $has_else = 0;
            for my $child (@children) {
                if (blessed($child) && $child->can('terminal')) {
                    my $val = $child->terminal;
                    $has_else = 1 if defined($val) && $val eq 'else';
                }
            }

            ok(!$has_else, 'ConditionalStatement should not have else clause');
        }
    }
};

subtest 'If-else with returns in both branches' => sub {
    my $code = q{
my $x = 5;
if ($x > 0) {
    return 42;
} else {
    return -42;
}
};

    my $result = parse_code($code);
    ok($result, 'Parse succeeded');

    SKIP: {
        skip "No parse result", 4 unless $result;

        my $cond_count = count_rule_nodes($result, 'ConditionalStatement');
        my $ret_count = count_rule_nodes($result, 'ReturnStatement');

        diag("ConditionalStatement nodes: $cond_count");
        diag("ReturnStatement nodes: $ret_count");

        is($cond_count, 1, 'Should have 1 ConditionalStatement node');
        is($ret_count, 2, 'Should have 2 ReturnStatement nodes');

        # Dump the structure
        diag("\n=== AST Structure for if-else both return ===");
        dump_ast($result);

        # Verify else clause exists
        my @conds = find_rule_nodes($result, 'ConditionalStatement');
        if (@conds) {
            my $cond_ast = $conds[0];
            my @children = $cond_ast->children->@*;

            my $has_else = 0;
            for my $child (@children) {
                if (blessed($child) && $child->can('terminal')) {
                    my $val = $child->terminal;
                    $has_else = 1 if defined($val) && $val eq 'else';
                }
            }

            ok($has_else, 'ConditionalStatement should have else clause');
        }
    }
};

subtest 'If-else with return only in true branch' => sub {
    my $code = q{
my $x = 5;
my $y = 0;
if ($x > 0) {
    return 42;
} else {
    $y = 100;
}
return $y;
};

    my $result = parse_code($code);
    ok($result, 'Parse succeeded');

    SKIP: {
        skip "No parse result", 3 unless $result;

        my $cond_count = count_rule_nodes($result, 'ConditionalStatement');
        my $ret_count = count_rule_nodes($result, 'ReturnStatement');

        diag("ConditionalStatement nodes: $cond_count");
        diag("ReturnStatement nodes: $ret_count");

        is($cond_count, 1, 'Should have 1 ConditionalStatement node');
        is($ret_count, 2, 'Should have 2 ReturnStatement nodes (one in if, one after)');

        # Dump the structure
        diag("\n=== AST Structure for if-else return in true only ===");
        dump_ast($result);
    }
};

done_testing();
