#!/usr/bin/env perl
# ABOUTME: Tests for BNF semantic actions that build Chalk::Grammar objects
# ABOUTME: Validates the BNF parser can construct actual grammar objects from parsed BNF

use 5.42.0;
use warnings;
use Test::More;

use lib 'lib';
use Chalk::Grammar::BNF;
use Chalk::Parser;
use Chalk::Semiring::Semantic;

# Test 1: Parse simple grammar rule and get Chalk::Grammar object
{
    my $bnf_grammar = Chalk::Grammar::BNF->grammar();
    my $semiring = Chalk::Semiring::Semantic->new(grammar => $bnf_grammar);
    my $parser = Chalk::Parser->new(
        grammar => $bnf_grammar,
        semiring => $semiring
    );

    my $result = $parser->parse_string("Foo -> 'bar'\n");
    ok($result, 'Semantic parsing returns a result');

    # Extract the grammar from the semantic result
    my $grammar = $result->context->extract;
    isa_ok($grammar, 'Chalk::Grammar', 'Result is a Chalk::Grammar object');
}

# Test 2: Parse grammar rule with nonterminal and verify rules
{
    my $bnf_grammar = Chalk::Grammar::BNF->grammar();
    my $semiring = Chalk::Semiring::Semantic->new(grammar => $bnf_grammar);
    my $parser = Chalk::Parser->new(
        grammar => $bnf_grammar,
        semiring => $semiring
    );

    my $result = $parser->parse_string("Rule -> 'foo' Bar\n");
    ok($result, 'Semantic parsing returns a result');

    my $grammar = $result->context->extract;
    isa_ok($grammar, 'Chalk::Grammar', 'Result is a Chalk::Grammar object');

    # Check that the grammar has a rule for 'Rule'
    my @rules = $grammar->rules_for('Rule');
    is(scalar(@rules), 1, 'Grammar has one rule for "Rule"');
    is($rules[0]->lhs, 'Rule', 'Rule LHS is "Rule"');
    is_deeply($rules[0]->rhs, ['foo', 'Bar'], 'Rule RHS is ["foo", "Bar"]');
}

# Test 3: Parse multiple grammar rules
{
    my $bnf_grammar = Chalk::Grammar::BNF->grammar();
    my $semiring = Chalk::Semiring::Semantic->new(grammar => $bnf_grammar);
    my $parser = Chalk::Parser->new(
        grammar => $bnf_grammar,
        semiring => $semiring
    );

    my $bnf = <<'EOF';
Foo -> 'a'
Bar -> 'b'
EOF

    my $result = $parser->parse_string($bnf);
    ok($result, 'Semantic parsing returns a result');

    my $grammar = $result->context->extract;
    isa_ok($grammar, 'Chalk::Grammar', 'Result is a Chalk::Grammar object');

    # Check both rules exist
    my @foo_rules = $grammar->rules_for('Foo');
    my @bar_rules = $grammar->rules_for('Bar');
    is(scalar(@foo_rules), 1, 'Grammar has one rule for "Foo"');
    is(scalar(@bar_rules), 1, 'Grammar has one rule for "Bar"');
}

# Test 4: Parse empty production
{
    my $bnf_grammar = Chalk::Grammar::BNF->grammar();
    my $semiring = Chalk::Semiring::Semantic->new(grammar => $bnf_grammar);
    my $parser = Chalk::Parser->new(
        grammar => $bnf_grammar,
        semiring => $semiring
    );

    my $result = $parser->parse_string("Empty ->\n");
    ok($result, 'Semantic parsing returns a result');

    my $grammar = $result->context->extract;
    isa_ok($grammar, 'Chalk::Grammar', 'Result is a Chalk::Grammar object');

    my @rules = $grammar->rules_for('Empty');
    is(scalar(@rules), 1, 'Grammar has one rule for "Empty"');
    is_deeply($rules[0]->rhs, [], 'Empty production has empty RHS');
}

# Test 5: Boolean semiring still works (backward compatibility)
{
    my $bnf_grammar = Chalk::Grammar::BNF->grammar();
    my $parser = Chalk::Parser->new(grammar => $bnf_grammar);

    my $result = $parser->parse_string("Foo -> 'bar'\n");
    ok($result, 'Boolean semiring still works');
}

done_testing();
