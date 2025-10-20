#!/usr/bin/env perl
# ABOUTME: Integration test for BNF semantic actions with parse_with_semantic_actions()
# ABOUTME: Validates Phase 4 - semantic actions can parse real BNF files

use 5.42.0;
use warnings;
use Test::More;

use lib 'lib';
use Chalk::BNF;
use Chalk::Grammar;

# Test 1: parse_with_semantic_actions() works with simple BNF
{
    my $bnf = "Foo -> 'bar'\n";
    my $grammar = Chalk::BNF::parse_with_semantic_actions($bnf);

    ok($grammar, 'parse_with_semantic_actions returns result');
    isa_ok($grammar, 'Chalk::Grammar', 'Result is Grammar object');

    my @rules = $grammar->rules_for('Foo');
    is(scalar(@rules), 1, 'Grammar has Foo rule');
    is_deeply($rules[0]->rhs, ['bar'], 'Foo RHS is [bar]');
}

# Test 2: Works with multiple rules
{
    my $bnf = <<'EOF';
Expr -> Term
Expr -> Expr '+' Term
Term -> 'number'
EOF

    my $grammar = Chalk::BNF::parse_with_semantic_actions($bnf);
    ok($grammar, 'Parses multiple rules');

    my @expr_rules = $grammar->rules_for('Expr');
    is(scalar(@expr_rules), 2, 'Expr has 2 alternatives');

    my @term_rules = $grammar->rules_for('Term');
    is(scalar(@term_rules), 1, 'Term has 1 rule');
}

# Test 3: Works with empty productions
{
    my $bnf = "OptionalComma ->\nOptionalComma -> ','\n";
    my $grammar = Chalk::BNF::parse_with_semantic_actions($bnf);

    ok($grammar, 'Parses empty production');
    my @rules = $grammar->rules_for('OptionalComma');
    is(scalar(@rules), 2, 'OptionalComma has 2 alternatives');

    # First alternative should be empty
    is_deeply($rules[0]->rhs, [], 'First alternative is epsilon');
    is_deeply($rules[1]->rhs, [','], 'Second alternative is comma');
}

# Test 4: Successfully parses grammar/bnf.bnf (self-describing BNF)
{
    open my $fh, '<', 'grammar/bnf.bnf' or die "Cannot open grammar/bnf.bnf: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    my $grammar = Chalk::BNF::parse_with_semantic_actions($content);
    ok($grammar, 'Parses grammar/bnf.bnf');
    isa_ok($grammar, 'Chalk::Grammar', 'bnf.bnf produces Grammar');

    # Check for expected nonterminals
    ok($grammar->rules_for('Grammar'), 'Has Grammar nonterminal');
    ok($grammar->rules_for('GrammarRule'), 'Has GrammarRule nonterminal');
    ok($grammar->rules_for('Terminal'), 'Has Terminal nonterminal');
}

# Test 5: Old parse_bnf_string() still works (backward compatibility)
{
    my $bnf = "Test -> 'foo' 'bar'\n";
    my $rules = Chalk::BNF::parse_bnf_string($bnf);

    ok($rules, 'parse_bnf_string still works');
    is(ref($rules), 'ARRAY', 'Returns arrayref');
    is(scalar(@$rules), 1, 'Has one rule');
    is_deeply($rules->[0], ['Test', ['foo', 'bar']], 'Rule structure correct');
}

# Test 6: build_chalk_grammar() still works
{
    my $bnf = "Start -> 'hello'\nStart -> 'world'\n";
    my $grammar = Chalk::BNF::build_chalk_grammar($bnf, 'Start');

    ok($grammar, 'build_chalk_grammar works');
    isa_ok($grammar, 'Chalk::Grammar');
    is($grammar->start_symbol, 'Start', 'Start symbol set correctly');

    my @rules = $grammar->rules_for('Start');
    is(scalar(@rules), 2, 'Start has 2 alternatives');
}

done_testing();
