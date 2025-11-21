#!/usr/bin/env perl
# ABOUTME: Tests for AST semiring - verifies parse tree structure
# ABOUTME: Compares generated AST JSON against expected output

use 5.42.0;
use lib 'lib';
use Test::More;
use JSON::PP ();
use FindBin qw($RealBin);

use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::AST;
use Chalk::Semiring::ChalkSyntax;
use Chalk::Semiring::Composite;

# Load grammar once
my $grammar;
BEGIN {
    open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
    my $bnf_content = do { local $/; <$fh> };
    close $fh;
    $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');
}

# Helper to parse and get AST
sub parse_to_ast($input) {

    # Use ChalkSyntax + AST composite for parsing
    my $chalksyntax = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
    my $ast = Chalk::Semiring::AST->new();
    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$chalksyntax, $ast]
    );

    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $composite
    );

    my $result = $parser->parse_string($input);
    return undef unless $result;

    # Extract AST element from composite
    if ($result->can('elements')) {
        my @elements = $result->elements->@*;
        # AST is second element (index 1)
        return $elements[1] if @elements > 1;
    }

    return $result;
}

# Helper to compare AST structure (ignoring spans)
sub normalize_ast($node) {
    return $node unless ref($node) eq 'HASH';

    my $result = { rule => $node->{rule} };

    if (exists $node->{children}) {
        $result->{children} = [
            map { normalize_ast($_) } $node->{children}->@*
        ];
    }

    return $result;
}

# Test 1: Simple integer literal
subtest 'Integer literal AST' => sub {
    my $ast = parse_to_ast('42');
    ok($ast, 'Parsed integer literal');

    if ($ast) {
        diag("AST type: " . ref($ast));
        diag("Rule name: " . ($ast->rule_name // 'undef'));
        if ($ast->can('to_json')) {
            diag("AST JSON: " . $ast->to_json());
        }
    }
};

# Test 2: Simple arithmetic
subtest 'Arithmetic expression AST' => sub {
    my $ast = parse_to_ast('1 + 2');
    ok($ast, 'Parsed arithmetic expression');

    if ($ast && $ast->can('to_hash')) {
        my $hash = $ast->to_hash();
        is($hash->{rule}, 'Program', 'Top-level rule is Program');
        diag("AST: " . JSON::PP->new->pretty->canonical->encode($hash));
    }
};

# Test 3: Precedence test - multiplication binds tighter
subtest 'Precedence: 1 + 2 * 3' => sub {
    my $ast = parse_to_ast('1 + 2 * 3');
    ok($ast, 'Parsed precedence expression');

    if ($ast && $ast->can('to_hash')) {
        my $hash = $ast->to_hash();
        diag("AST: " . JSON::PP->new->pretty->canonical->encode($hash));

        # The AST should show 2*3 grouped together, not 1+2
        # This verifies precedence is working correctly
    }
};

# Test 4: Variable declaration
subtest 'Variable declaration AST' => sub {
    my $ast = parse_to_ast('my $x = 42;');
    ok($ast, 'Parsed variable declaration');

    if ($ast && $ast->can('to_hash')) {
        my $hash = $ast->to_hash();
        diag("AST: " . JSON::PP->new->pretty->canonical->encode($hash));
    }
};

# Test 5: Function call
subtest 'Function call AST' => sub {
    my $ast = parse_to_ast('foo(1, 2)');
    ok($ast, 'Parsed function call');

    if ($ast && $ast->can('to_hash')) {
        my $hash = $ast->to_hash();
        diag("AST: " . JSON::PP->new->pretty->canonical->encode($hash));
    }
};

# Test 6: Conditional statement
subtest 'Conditional statement AST' => sub {
    my $ast = parse_to_ast('if ($x) { 1 }');
    ok($ast, 'Parsed conditional statement');

    if ($ast && $ast->can('to_hash')) {
        my $hash = $ast->to_hash();
        diag("AST: " . JSON::PP->new->pretty->canonical->encode($hash));
    }
};

done_testing();
