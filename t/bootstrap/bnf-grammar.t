# ABOUTME: Tests for BNF meta-grammar data structure representation.
# ABOUTME: Verifies the 10-rule meta-grammar is correctly encoded as Rule/Symbol objects.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::BNF;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;

# Test 1: Grammar returns an arrayref
my $grammar = Chalk::Grammar::BNF->grammar();
ok(ref($grammar) eq 'ARRAY', 'grammar() returns an arrayref');

# Test 2: Verify exactly 10 rules
is(scalar($grammar->@*), 10, 'grammar has exactly 10 rules');

# Test 3: Verify rule names are correct and in order
my @expected_names = qw(Grammar Rule Alternatives Sequence Element Atom Quantifier Comment Identifier InlineRegex);
my @actual_names = map { $_->name() } $grammar->@*;
is_deeply(\@actual_names, \@expected_names, 'rule names are correct and in order');

# Test 4: Verify Grammar rule structure
# Grammar ::= /(?:\s|#[^\n]*)*/ Rule+
my $grammar_rule = $grammar->[0];
is($grammar_rule->name(), 'Grammar', 'first rule is Grammar');
is($grammar_rule->alternative_count(), 1, 'Grammar has 1 alternative');
my $grammar_alt = $grammar_rule->expressions()->[0];
is(scalar($grammar_alt->@*), 2, 'Grammar alternative has 2 symbols');

my $ws_symbol = $grammar_alt->[0];
ok($ws_symbol->is_terminal(), 'first symbol is terminal');
is($ws_symbol->value(), '(?:\\s|#[^\\n]*)*', 'whitespace pattern is correct');
ok(!defined $ws_symbol->quantifier(), 'whitespace symbol has no quantifier');

my $rule_symbol = $grammar_alt->[1];
ok($rule_symbol->is_reference(), 'second symbol is reference');
is($rule_symbol->value(), 'Rule', 'references Rule');
is($rule_symbol->quantifier(), '+', 'has + quantifier');

# Test 5: Verify Rule has 8 symbols
# Rule ::= Identifier /(?:\s|#[^\n]*)*/ /::=/ /(?:\s|#[^\n]*)*/ Alternatives /(?:\s|#[^\n]*)*/ /;/ /(?:\s|#[^\n]*)*/
my $rule_rule = $grammar->[1];
is($rule_rule->name(), 'Rule', 'second rule is Rule');
is($rule_rule->alternative_count(), 1, 'Rule has 1 alternative');
my $rule_alt = $rule_rule->expressions()->[0];
is(scalar($rule_alt->@*), 8, 'Rule alternative has 8 symbols');

# Verify the sequence of symbols
is($rule_alt->[0]->value(), 'Identifier', 'first symbol is Identifier reference');
ok($rule_alt->[0]->is_reference(), 'Identifier is a reference');
is($rule_alt->[1]->value(), '(?:\\s|#[^\\n]*)*', 'second symbol is whitespace');
ok($rule_alt->[1]->is_terminal(), 'whitespace is terminal');
is($rule_alt->[2]->value(), '::=', 'third symbol is ::=');
ok($rule_alt->[2]->is_terminal(), '::= is terminal');

# Test 6: Verify Alternatives has 2 alternatives
# Alternatives ::= Sequence /(?:\s|#[^\n]*)*/ /\|/ /(?:\s|#[^\n]*)*/ Alternatives | Sequence
my $alts_rule = $grammar->[2];
is($alts_rule->name(), 'Alternatives', 'third rule is Alternatives');
is($alts_rule->alternative_count(), 2, 'Alternatives has 2 alternatives');

my $alts_recursive = $alts_rule->expressions()->[0];
is(scalar($alts_recursive->@*), 5, 'recursive alternative has 5 symbols');
is($alts_recursive->[0]->value(), 'Sequence', 'first is Sequence reference');
is($alts_recursive->[2]->value(), '\\|', 'pipe symbol is correct');
is($alts_recursive->[4]->value(), 'Alternatives', 'recursive reference to Alternatives');

my $alts_base = $alts_rule->expressions()->[1];
is(scalar($alts_base->@*), 1, 'base case has 1 symbol');
is($alts_base->[0]->value(), 'Sequence', 'base case is just Sequence');

# Test 7: Verify Sequence has 2 alternatives
# Sequence ::= Sequence_Element /(?:\s|#[^\n]*)+/ Sequence | Sequence_Element
# Note: Sequence_Element should reference 'Element' since that's the actual rule name
my $seq_rule = $grammar->[3];
is($seq_rule->name(), 'Sequence', 'fourth rule is Sequence');
is($seq_rule->alternative_count(), 2, 'Sequence has 2 alternatives');

my $seq_recursive = $seq_rule->expressions()->[0];
is(scalar($seq_recursive->@*), 3, 'recursive alternative has 3 symbols');
is($seq_recursive->[0]->value(), 'Element', 'first is Element reference');
is($seq_recursive->[1]->value(), '(?:\\s|#[^\\n]*)+', 'required whitespace pattern');
is($seq_recursive->[2]->value(), 'Sequence', 'recursive reference to Sequence');

my $seq_base = $seq_rule->expressions()->[1];
is(scalar($seq_base->@*), 1, 'base case has 1 symbol');
is($seq_base->[0]->value(), 'Element', 'base case is just Element');

# Test 8: Verify Element rule
# Element ::= Atom Quantifier?
my $elem_rule = $grammar->[4];
is($elem_rule->name(), 'Element', 'fifth rule is Element');
is($elem_rule->alternative_count(), 1, 'Element has 1 alternative');
my $elem_alt = $elem_rule->expressions()->[0];
is(scalar($elem_alt->@*), 2, 'Element has 2 symbols');
is($elem_alt->[0]->value(), 'Atom', 'first is Atom reference');
is($elem_alt->[1]->value(), 'Quantifier', 'second is Quantifier reference');
is($elem_alt->[1]->quantifier(), '?', 'Quantifier has ? quantifier');

# Test 9: Verify Atom has 2 alternatives
# Atom ::= Identifier | InlineRegex
my $atom_rule = $grammar->[5];
is($atom_rule->name(), 'Atom', 'sixth rule is Atom');
is($atom_rule->alternative_count(), 2, 'Atom has 2 alternatives');
is($atom_rule->expressions()->[0][0]->value(), 'Identifier', 'first alt is Identifier');
is($atom_rule->expressions()->[1][0]->value(), 'InlineRegex', 'second alt is InlineRegex');

# Test 10: Verify Quantifier has 3 alternatives
# Quantifier ::= /\*/ | /\+/ | /\?/
my $quant_rule = $grammar->[6];
is($quant_rule->name(), 'Quantifier', 'seventh rule is Quantifier');
is($quant_rule->alternative_count(), 3, 'Quantifier has 3 alternatives');
is($quant_rule->expressions()->[0][0]->value(), '\\*', 'first is * literal');
is($quant_rule->expressions()->[1][0]->value(), '\\+', 'second is + literal');
is($quant_rule->expressions()->[2][0]->value(), '\\?', 'third is ? literal');

# Test 11: Verify terminal patterns for Identifier and InlineRegex
# Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/
my $ident_rule = $grammar->[8];
is($ident_rule->name(), 'Identifier', 'ninth rule is Identifier');
is($ident_rule->expressions()->[0][0]->value(), '[A-Za-z_][A-Za-z_0-9]*', 'Identifier pattern is correct');

# InlineRegex ::= /\/(?:[^\/\\]|\\.)*\//
my $regex_rule = $grammar->[9];
is($regex_rule->name(), 'InlineRegex', 'tenth rule is InlineRegex');
is($regex_rule->expressions()->[0][0]->value(), '\\/(?:[^\\/\\\\]|\\\\.)*\\/', 'InlineRegex pattern is correct');

# Test 12: Verify all references point to valid rule names
my %rule_names = map { $_->name() => 1 } $grammar->@*;
for my $rule ($grammar->@*) {
    for my $alt ($rule->expressions()->@*) {
        for my $symbol ($alt->@*) {
            if ($symbol->is_reference()) {
                ok(exists $rule_names{$symbol->value()},
                   "reference '${\$symbol->value()}' from rule '${\$rule->name()}' points to valid rule");
            }
        }
    }
}

# Test 13: Verify each Rule object is actually a Chalk::Grammar::Rule
for my $rule ($grammar->@*) {
    isa_ok($rule, 'Chalk::Grammar::Rule', "rule '${\$rule->name()}'");
}

# Test 14: Verify Comment rule
# Comment ::= /#[^\n]*/
my $comment_rule = $grammar->[7];
is($comment_rule->name(), 'Comment', 'eighth rule is Comment');
is($comment_rule->alternative_count(), 1, 'Comment has 1 alternative');
is($comment_rule->expressions()->[0][0]->value(), '#[^\\n]*', 'Comment pattern is correct');

done_testing();
