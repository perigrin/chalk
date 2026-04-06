# ABOUTME: Integration test for Phase 2a - grammar data model construction for BNF
# ABOUTME: Verifies that Grammar::Symbol and Grammar::Rule represent the BNF meta-grammar correctly
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Symbol;
use Chalk::Grammar::Rule;

# Test 1: Build a simple terminal rule
# Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/
{
    my $sym = Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => '[A-Za-z_][A-Za-z_0-9]*',
    );

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'Identifier',
        expressions => [[$sym]],
    );

    isa_ok($rule, 'Chalk::Grammar::Rule', 'created Identifier rule');
    is($rule->name(), 'Identifier', 'rule name is Identifier');
    is($rule->alternative_count(), 1, 'rule has 1 alternative');

    my $alt = $rule->expressions()->[0];
    is(scalar($alt->@*), 1, 'alternative has 1 symbol');
    isa_ok($alt->[0], 'Chalk::Grammar::Symbol', 'symbol is a Symbol object');
    ok($alt->[0]->is_terminal(), 'symbol type is terminal');
    is($alt->[0]->value(), '[A-Za-z_][A-Za-z_0-9]*', 'symbol value is pattern');
}

# Test 2: Build a rule with alternatives
# Atom ::= Identifier | InlineRegex
{
    my $ident_sym = Chalk::Grammar::Symbol->new(type => 'reference', value => 'Identifier');
    my $regex_sym = Chalk::Grammar::Symbol->new(type => 'reference', value => 'InlineRegex');

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'Atom',
        expressions => [[$ident_sym], [$regex_sym]],
    );

    isa_ok($rule, 'Chalk::Grammar::Rule', 'created Atom rule');
    is($rule->name(), 'Atom', 'rule name is Atom');
    is($rule->alternative_count(), 2, 'Atom has 2 alternatives');
    is($rule->expressions()->[0][0]->value(), 'Identifier', 'first alt is Identifier');
    is($rule->expressions()->[1][0]->value(), 'InlineRegex', 'second alt is InlineRegex');
}

# Test 3: Build a rule with a quantifier
# Grammar ::= Rule+
{
    my $sym = Chalk::Grammar::Symbol->new(
        type       => 'reference',
        value      => 'Rule',
        quantifier => '+',
    );

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'Grammar',
        expressions => [[$sym]],
    );

    isa_ok($rule, 'Chalk::Grammar::Rule', 'created Grammar rule');
    is($rule->name(), 'Grammar', 'rule name is Grammar');

    my $alt_sym = $rule->expressions()->[0][0];
    is($alt_sym->quantifier(), '+', 'symbol has + quantifier');
    ok($alt_sym->is_quantified(), 'symbol reports as quantified');
}

# Test 4: Build a sequence (multiple symbols)
# Element ::= Atom Quantifier
{
    my $atom_sym  = Chalk::Grammar::Symbol->new(type => 'reference', value => 'Atom');
    my $quant_sym = Chalk::Grammar::Symbol->new(type => 'reference', value => 'Quantifier');

    my $rule = Chalk::Grammar::Rule->new(
        name        => 'Element',
        expressions => [[$atom_sym, $quant_sym]],
    );

    isa_ok($rule, 'Chalk::Grammar::Rule', 'created Element rule');
    my $alt = $rule->expressions()->[0];
    is(scalar($alt->@*), 2, 'sequence has 2 elements');
    is($alt->[0]->value(), 'Atom', 'first element is Atom');
    is($alt->[1]->value(), 'Quantifier', 'second element is Quantifier');
}

# Test 5: Symbol accessor methods
{
    my $sym = Chalk::Grammar::Symbol->new(
        type  => 'reference',
        value => 'SomeRule',
    );

    ok($sym->is_reference(), 'reference symbol: is_reference() is true');
    ok(!$sym->is_terminal(), 'reference symbol: is_terminal() is false');
    ok(!$sym->is_quantified(), 'symbol without quantifier: is_quantified() is false');

    my $sym_term = Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => '[0-9]+',
    );
    ok($sym_term->is_terminal(), 'terminal symbol: is_terminal() is true');
    ok(!$sym_term->is_reference(), 'terminal symbol: is_reference() is false');
}

# Test 6: Symbols with all three quantifiers
{
    for my $q (qw(* + ?)) {
        my $sym = Chalk::Grammar::Symbol->new(
            type       => 'reference',
            value      => 'Element',
            quantifier => $q,
        );
        is($sym->quantifier(), $q, "symbol with quantifier '$q'");
        ok($sym->is_quantified(), "symbol with '$q' is quantified");
    }
}

# Test 7: Both terminal and reference symbol types
{
    my $terminal_sym = Chalk::Grammar::Symbol->new(type => 'terminal', value => 'foo');
    ok($terminal_sym->is_terminal(), 'created terminal symbol');

    my $reference_sym = Chalk::Grammar::Symbol->new(type => 'reference', value => 'foo');
    ok($reference_sym->is_reference(), 'created reference symbol');
}

# Test 8: Complex multi-symbol sequence
# Rule ::= Identifier /ws/ /::=/ /ws/ Alternatives /ws/ /;/ /ws/
{
    my $rule = Chalk::Grammar::Rule->new(
        name => 'Rule',
        expressions => [[
            Chalk::Grammar::Symbol->new(type => 'reference', value => 'Identifier'),
            Chalk::Grammar::Symbol->new(type => 'terminal',  value => '(?:\\s|#[^\\n]*)*'),
            Chalk::Grammar::Symbol->new(type => 'terminal',  value => '::='),
            Chalk::Grammar::Symbol->new(type => 'terminal',  value => '(?:\\s|#[^\\n]*)*'),
            Chalk::Grammar::Symbol->new(type => 'reference', value => 'Alternatives'),
            Chalk::Grammar::Symbol->new(type => 'terminal',  value => '(?:\\s|#[^\\n]*)*'),
            Chalk::Grammar::Symbol->new(type => 'terminal',  value => ';'),
            Chalk::Grammar::Symbol->new(type => 'terminal',  value => '(?:\\s|#[^\\n]*)*'),
        ]],
    );

    isa_ok($rule, 'Chalk::Grammar::Rule', 'created complex Rule');
    is($rule->name(), 'Rule', 'rule name is Rule');
    my $alt = $rule->expressions()->[0];
    is(scalar($alt->@*), 8, 'Rule has 8 symbols in sequence');
}

done_testing();
