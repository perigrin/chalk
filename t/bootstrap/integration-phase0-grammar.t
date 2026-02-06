# ABOUTME: Integration test for Phase 0 - BNF meta-grammar data model representation
# ABOUTME: Verifies that the 10-rule BNF meta-grammar can be correctly represented as Rule/Symbol objects
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::BNF;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;

# Get the BNF meta-grammar
my $grammar = Chalk::Grammar::BNF->grammar();

# Test 1: Grammar is an arrayref
ok(ref($grammar) eq 'ARRAY', 'grammar() returns an arrayref');

# Test 2: Verify exactly 10 rules (as per spec)
is(scalar($grammar->@*), 10, 'grammar has exactly 10 rules');

# Test 3: Verify rule names match the BNF specification
my @expected_names = qw(Grammar Rule Alternatives Sequence Element Atom Quantifier Comment Identifier InlineRegex);
my @actual_names = map { $_->name() } $grammar->@*;
is_deeply(\@actual_names, \@expected_names, 'rule names match BNF specification');

# Test 4: Grammar rule structure - Grammar ::= /(?:\s|#[^\n]*)*/ Rule+
{
    my $grammar_rule = $grammar->[0];
    is($grammar_rule->name(), 'Grammar', 'Grammar rule name');
    is($grammar_rule->alternative_count(), 1, 'Grammar has 1 alternative');

    my $alt = $grammar_rule->expressions()->[0];
    is(scalar($alt->@*), 2, 'Grammar has 2 symbols');

    my ($ws, $rule_ref) = $alt->@*;
    ok($ws->is_terminal(), 'first symbol is terminal (whitespace)');
    is($ws->value(), '(?:\\s|#[^\\n]*)*', 'whitespace pattern correct');

    ok($rule_ref->is_reference(), 'second symbol is reference');
    is($rule_ref->value(), 'Rule', 'references Rule nonterminal');
    is($rule_ref->quantifier(), '+', 'Rule has + quantifier (one or more)');
}

# Test 5: Rule structure - Rule ::= Identifier /ws*/ /::=/ /ws*/ Alternatives /ws*/ /;/ /ws*/
{
    my $rule = $grammar->[1];
    is($rule->name(), 'Rule', 'Rule rule name');
    is($rule->alternative_count(), 1, 'Rule has 1 alternative');

    my $alt = $rule->expressions()->[0];
    is(scalar($alt->@*), 8, 'Rule has 8 symbols');

    # Verify sequence: Identifier, ws, ::=, ws, Alternatives, ws, ;, ws
    ok($alt->[0]->is_reference(), 'symbol 0 is reference (Identifier)');
    is($alt->[0]->value(), 'Identifier', 'symbol 0 value');

    ok($alt->[2]->is_terminal(), 'symbol 2 is terminal (::=)');
    is($alt->[2]->value(), '::=', 'symbol 2 value');

    ok($alt->[4]->is_reference(), 'symbol 4 is reference (Alternatives)');
    is($alt->[4]->value(), 'Alternatives', 'symbol 4 value');

    ok($alt->[6]->is_terminal(), 'symbol 6 is terminal (;)');
    is($alt->[6]->value(), ';', 'symbol 6 value');
}

# Test 6: Alternatives structure - 2 alternatives (recursive and base case)
{
    my $rule = $grammar->[2];
    is($rule->name(), 'Alternatives', 'Alternatives rule name');
    is($rule->alternative_count(), 2, 'Alternatives has 2 alternatives');

    # First alternative: Sequence /ws*/ /\|/ /ws*/ Alternatives (recursive)
    my $recursive_alt = $rule->expressions()->[0];
    is(scalar($recursive_alt->@*), 5, 'recursive alternative has 5 symbols');
    is($recursive_alt->[0]->value(), 'Sequence', 'starts with Sequence');
    is($recursive_alt->[2]->value(), '\\|', 'pipe symbol');
    is($recursive_alt->[4]->value(), 'Alternatives', 'recursive reference');

    # Second alternative: Sequence (base case)
    my $base_alt = $rule->expressions()->[1];
    is(scalar($base_alt->@*), 1, 'base case has 1 symbol');
    is($base_alt->[0]->value(), 'Sequence', 'base case is Sequence');
}

# Test 7: Sequence structure - 2 alternatives (recursive and base case)
{
    my $rule = $grammar->[3];
    is($rule->name(), 'Sequence', 'Sequence rule name');
    is($rule->alternative_count(), 2, 'Sequence has 2 alternatives');

    # First alternative: Element /ws+/ Sequence (recursive)
    my $recursive_alt = $rule->expressions()->[0];
    is(scalar($recursive_alt->@*), 3, 'recursive alternative has 3 symbols');
    is($recursive_alt->[0]->value(), 'Element', 'starts with Element');
    is($recursive_alt->[1]->value(), '(?:\\s|#[^\\n]*)+', 'required whitespace');
    is($recursive_alt->[2]->value(), 'Sequence', 'recursive reference');

    # Second alternative: Element (base case)
    my $base_alt = $rule->expressions()->[1];
    is(scalar($base_alt->@*), 1, 'base case has 1 symbol');
    is($base_alt->[0]->value(), 'Element', 'base case is Element');
}

# Test 8: Element structure - Element ::= Atom Quantifier?
{
    my $rule = $grammar->[4];
    is($rule->name(), 'Element', 'Element rule name');
    is($rule->alternative_count(), 1, 'Element has 1 alternative');

    my $alt = $rule->expressions()->[0];
    is(scalar($alt->@*), 2, 'Element has 2 symbols');

    ok($alt->[0]->is_reference(), 'first symbol is Atom reference');
    is($alt->[0]->value(), 'Atom', 'Atom value');

    ok($alt->[1]->is_reference(), 'second symbol is Quantifier reference');
    is($alt->[1]->value(), 'Quantifier', 'Quantifier value');
    is($alt->[1]->quantifier(), '?', 'Quantifier is optional (? quantifier)');
}

# Test 9: Atom structure - 2 alternatives (Identifier | InlineRegex)
{
    my $rule = $grammar->[5];
    is($rule->name(), 'Atom', 'Atom rule name');
    is($rule->alternative_count(), 2, 'Atom has 2 alternatives');

    my $alt1 = $rule->expressions()->[0];
    is(scalar($alt1->@*), 1, 'first alternative has 1 symbol');
    is($alt1->[0]->value(), 'Identifier', 'first alternative is Identifier');

    my $alt2 = $rule->expressions()->[1];
    is(scalar($alt2->@*), 1, 'second alternative has 1 symbol');
    is($alt2->[0]->value(), 'InlineRegex', 'second alternative is InlineRegex');
}

# Test 10: Quantifier structure - 3 alternatives (*, +, ?)
{
    my $rule = $grammar->[6];
    is($rule->name(), 'Quantifier', 'Quantifier rule name');
    is($rule->alternative_count(), 3, 'Quantifier has 3 alternatives');

    ok($rule->expressions()->[0][0]->is_terminal(), 'first alternative is terminal');
    is($rule->expressions()->[0][0]->value(), '\\*', 'first alternative is *');

    ok($rule->expressions()->[1][0]->is_terminal(), 'second alternative is terminal');
    is($rule->expressions()->[1][0]->value(), '\\+', 'second alternative is +');

    ok($rule->expressions()->[2][0]->is_terminal(), 'third alternative is terminal');
    is($rule->expressions()->[2][0]->value(), '\\?', 'third alternative is ?');
}

# Test 11: Comment structure - Comment ::= /#[^\n]*/
{
    my $rule = $grammar->[7];
    is($rule->name(), 'Comment', 'Comment rule name');
    is($rule->alternative_count(), 1, 'Comment has 1 alternative');

    my $alt = $rule->expressions()->[0];
    is(scalar($alt->@*), 1, 'Comment has 1 symbol');
    ok($alt->[0]->is_terminal(), 'Comment symbol is terminal');
    is($alt->[0]->value(), '#[^\\n]*', 'Comment pattern');
}

# Test 12: Identifier structure - Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/
{
    my $rule = $grammar->[8];
    is($rule->name(), 'Identifier', 'Identifier rule name');
    is($rule->alternative_count(), 1, 'Identifier has 1 alternative');

    my $alt = $rule->expressions()->[0];
    is(scalar($alt->@*), 1, 'Identifier has 1 symbol');
    ok($alt->[0]->is_terminal(), 'Identifier symbol is terminal');
    is($alt->[0]->value(), '[A-Za-z_][A-Za-z_0-9]*', 'Identifier pattern');
}

# Test 13: InlineRegex structure - InlineRegex ::= /\/(?:[^\/\\]|\\.)*\//
{
    my $rule = $grammar->[9];
    is($rule->name(), 'InlineRegex', 'InlineRegex rule name');
    is($rule->alternative_count(), 1, 'InlineRegex has 1 alternative');

    my $alt = $rule->expressions()->[0];
    is(scalar($alt->@*), 1, 'InlineRegex has 1 symbol');
    ok($alt->[0]->is_terminal(), 'InlineRegex symbol is terminal');
    is($alt->[0]->value(), '\\/(?:[^\\/\\\\]|\\\\.)*\\/', 'InlineRegex pattern');
}

# Test 14: Verify to_string() produces reasonable output for each rule
{
    for my $rule ($grammar->@*) {
        my $str = $rule->to_string();
        like($str, qr/^\w+\s+::=\s+.*\s+;$/, "rule '${\$rule->name()}' to_string() format");
        like($str, qr/^${\$rule->name()}\s+::=/, "to_string() starts with rule name");
    }
}

# Test 15: Cross-reference validation - all references point to valid rules
{
    my %rule_names = map { $_->name() => 1 } $grammar->@*;

    for my $rule ($grammar->@*) {
        for my $alt ($rule->expressions()->@*) {
            for my $symbol ($alt->@*) {
                if ($symbol->is_reference()) {
                    my $ref_name = $symbol->value();
                    ok(exists $rule_names{$ref_name},
                       "reference '$ref_name' in rule '${\$rule->name()}' points to valid rule");
                }
            }
        }
    }
}

# Test 16: Verify terminal vs reference classification
{
    my $terminal_count = 0;
    my $reference_count = 0;

    for my $rule ($grammar->@*) {
        for my $alt ($rule->expressions()->@*) {
            for my $symbol ($alt->@*) {
                if ($symbol->is_terminal()) {
                    $terminal_count++;
                    ok(!$symbol->is_reference(), "terminal symbol is not reference");
                }
                if ($symbol->is_reference()) {
                    $reference_count++;
                    ok(!$symbol->is_terminal(), "reference symbol is not terminal");
                }
            }
        }
    }

    ok($terminal_count > 0, "grammar has terminal symbols ($terminal_count)");
    ok($reference_count > 0, "grammar has reference symbols ($reference_count)");
}

# Test 17: Verify quantifier usage
{
    my $quantified_count = 0;
    my %quantifier_types;

    for my $rule ($grammar->@*) {
        for my $alt ($rule->expressions()->@*) {
            for my $symbol ($alt->@*) {
                if ($symbol->is_quantified()) {
                    $quantified_count++;
                    $quantifier_types{$symbol->quantifier()}++;
                }
            }
        }
    }

    ok($quantified_count > 0, "grammar has quantified symbols ($quantified_count)");
    ok(exists $quantifier_types{'+'}, "grammar uses + quantifier");
    ok(exists $quantifier_types{'?'}, "grammar uses ? quantifier");
}

done_testing();
