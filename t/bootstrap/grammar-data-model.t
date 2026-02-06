# ABOUTME: Tests for Chalk::Grammar::Symbol and Chalk::Grammar::Rule data model.
# ABOUTME: Verifies construction, accessors, and basic predicates work correctly.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Symbol;
use Chalk::Grammar::Rule;

# Test Symbol construction and accessors
{
    my $terminal = Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => '\s+',
    );

    is($terminal->type, 'terminal', 'terminal type');
    is($terminal->value, '\s+', 'terminal value');
    ok(!defined $terminal->quantifier, 'no quantifier');
    ok($terminal->is_terminal, 'is_terminal predicate');
    ok(!$terminal->is_reference, 'not is_reference');
    ok(!$terminal->is_quantified, 'not is_quantified');
    is($terminal->to_string, '/\s+/', 'terminal to_string');
}

{
    my $reference = Chalk::Grammar::Symbol->new(
        type  => 'reference',
        value => 'Identifier',
    );

    is($reference->type, 'reference', 'reference type');
    is($reference->value, 'Identifier', 'reference value');
    ok($reference->is_reference, 'is_reference predicate');
    ok(!$reference->is_terminal, 'not is_terminal');
    is($reference->to_string, 'Identifier', 'reference to_string');
}

{
    my $quantified = Chalk::Grammar::Symbol->new(
        type       => 'reference',
        value      => 'Rule',
        quantifier => '+',
    );

    is($quantified->quantifier, '+', 'quantifier accessor');
    ok($quantified->is_quantified, 'is_quantified predicate');
    is($quantified->to_string, 'Rule+', 'quantified to_string');
}

# Test Rule construction and accessors
{
    my $identifier_sym = Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => '[A-Za-z_][A-Za-z_0-9]*',
    );

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'Identifier',
        expressions => [
            [$identifier_sym],
        ],
    );

    is($rule->name, 'Identifier', 'rule name');
    is($rule->alternative_count, 1, 'single alternative');
    ok($rule->is_terminal_rule, 'is_terminal_rule predicate');
    like($rule->to_string, qr/Identifier ::= .* ;/, 'rule to_string format');
}

{
    my $identifier = Chalk::Grammar::Symbol->new(
        type  => 'reference',
        value => 'Identifier',
    );

    my $inline_regex = Chalk::Grammar::Symbol->new(
        type  => 'reference',
        value => 'InlineRegex',
    );

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'Atom',
        expressions => [
            [$identifier],
            [$inline_regex],
        ],
    );

    is($rule->alternative_count, 2, 'two alternatives');
    ok(!$rule->is_terminal_rule, 'not is_terminal_rule (has references)');
    like($rule->to_string, qr/Atom ::= Identifier \| InlineRegex ;/, 'multi-alternative to_string');
}

{
    my $atom = Chalk::Grammar::Symbol->new(
        type  => 'reference',
        value => 'Atom',
    );

    my $quantifier = Chalk::Grammar::Symbol->new(
        type       => 'reference',
        value      => 'Quantifier',
        quantifier => '?',
    );

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'Element',
        expressions => [
            [$atom, $quantifier],
        ],
    );

    is($rule->alternative_count, 1, 'sequence alternative');
    like($rule->to_string, qr/Element ::= Atom Quantifier\? ;/, 'sequence to_string');
}

done_testing;
