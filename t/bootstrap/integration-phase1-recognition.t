# ABOUTME: Integration test for Phase 1a - Earley parser recognition with BNF meta-grammar
# ABOUTME: Verifies that the Earley parser with Boolean semiring can parse valid BNF inputs
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::BNF;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Desugar qw(desugar_grammar);

# Get the BNF meta-grammar
my $grammar = Chalk::Grammar::BNF->grammar();
my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();

# IMPORTANT: The current Earley parser may not support quantifiers on nonterminal references.
# Quantifiers like Rule+ in "Grammar ::= /ws*/ Rule+" need to be desugared into helper rules.
# If this test fails due to quantifier issues, mark those tests as TODO.

# For now, test with a simplified grammar without quantifiers on nonterminals
# Build a minimal BNF grammar manually for testing

# Helper to create terminal symbol
sub terminal($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => $value,
    );
}

# Helper to create reference symbol
sub reference($value, $quant = undef) {
    return Chalk::Grammar::Symbol->new(
        type       => 'reference',
        value      => $value,
        quantifier => $quant,
    );
}

# Test 1: Simple terminal-only rule
# Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/
{
    my $test_grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Identifier')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Identifier',
            expressions => [[terminal('[A-Za-z_][A-Za-z_0-9]*')]],
        ),
    ];

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $test_grammar,
        semiring => $semiring,
    );

    ok($parser->parse('foo'), "accepts 'foo' as Identifier");
    ok($parser->parse('Element'), "accepts 'Element' as Identifier");
    ok($parser->parse('_private'), "accepts '_private' as Identifier");
    ok($parser->parse('var123'), "accepts 'var123' as Identifier");
    ok(!$parser->parse('123'), "rejects '123' (starts with digit)");
    ok(!$parser->parse(''), "rejects empty string");
}

# Test 2: InlineRegex terminal
# InlineRegex ::= /\/(?:[^\/\\]|\\.)*\//
{
    my $test_grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('InlineRegex')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'InlineRegex',
            expressions => [[terminal('\\/(?:[^\\/\\\\]|\\\\.)*\\/')]],
        ),
    ];

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $test_grammar,
        semiring => $semiring,
    );

    ok($parser->parse('/[a-z]+/'), "accepts '/[a-z]+/' as InlineRegex");
    ok($parser->parse('/\\d+/'), "accepts '/\\d+/' as InlineRegex (escaped)");
    # /[^/]+/ has unescaped / inside character class - pattern terminates early
    ok(!$parser->parse('/[^/]+/'), "rejects '/[^/]+/' (unescaped / inside)");
    ok(!$parser->parse('[a-z]+'), "rejects '[a-z]+' (no slashes)");
    # // matches the pattern - * allows zero chars between delimiters
    ok($parser->parse('//'), "accepts '//' (empty regex is valid)");
}

# Test 3: Atom rule with alternatives (Identifier | InlineRegex)
# Atom ::= Identifier | InlineRegex
{
    my $test_grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Atom')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Atom',
            expressions => [
                [reference('Identifier')],
                [reference('InlineRegex')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Identifier',
            expressions => [[terminal('[A-Za-z_][A-Za-z_0-9]*')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'InlineRegex',
            expressions => [[terminal('\\/(?:[^\\/\\\\]|\\\\.)*\\/')]],
        ),
    ];

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $test_grammar,
        semiring => $semiring,
    );

    ok($parser->parse('Element'), "accepts 'Element' as Identifier via Atom");
    ok($parser->parse('/[a-z]+/'), "accepts '/[a-z]+/' as InlineRegex via Atom");
    ok(!$parser->parse('123'), "rejects '123' (not valid Identifier or InlineRegex)");
    ok(!$parser->parse('::='), "rejects '::=' (not an Atom)");
}

# Test 4: Quantifier rule with 3 alternatives
# Quantifier ::= /\*/ | /\+/ | /\?/
{
    my $test_grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Quantifier')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Quantifier',
            expressions => [
                [terminal('\\*')],
                [terminal('\\+')],
                [terminal('\\?')],
            ],
        ),
    ];

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $test_grammar,
        semiring => $semiring,
    );

    ok($parser->parse('*'), "accepts '*' as Quantifier");
    ok($parser->parse('+'), "accepts '+' as Quantifier");
    ok($parser->parse('?'), "accepts '?' as Quantifier");
    ok(!$parser->parse('!'), "rejects '!' (not a quantifier)");
    ok(!$parser->parse('**'), "rejects '**' (only one quantifier)");
}

# Test 5: Element rule (no quantifier) - Element ::= Atom
# Simplified version without optional Quantifier for now
{
    my $test_grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Element')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Element',
            expressions => [[reference('Atom')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Atom',
            expressions => [
                [reference('Identifier')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Identifier',
            expressions => [[terminal('[A-Za-z_][A-Za-z_0-9]*')]],
        ),
    ];

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $test_grammar,
        semiring => $semiring,
    );

    ok($parser->parse('foo'), "accepts 'foo' as Element (via Atom via Identifier)");
    ok($parser->parse('Element'), "accepts 'Element' as Element");
}

# Test 6: Sequence of two Elements (no whitespace for simplicity)
# Sequence ::= Element Element
{
    my $test_grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Sequence')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Sequence',
            expressions => [[reference('Element'), reference('Element')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Element',
            expressions => [[terminal('[a-z]')]],
        ),
    ];

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $test_grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ab'), "accepts 'ab' as Sequence of two Elements");
    ok($parser->parse('xy'), "accepts 'xy' as Sequence");
    ok(!$parser->parse('a'), "rejects 'a' (needs two elements)");
    ok(!$parser->parse('abc'), "rejects 'abc' (too many elements)");
}

# Test 7: Alternatives with pipe - Alternatives ::= Sequence | Sequence
# Simplified: two alternatives without recursion
{
    my $test_grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Alternatives')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Alternatives',
            expressions => [
                [terminal('a')],
                [terminal('b')],
            ],
        ),
    ];

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $test_grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a'), "accepts 'a' via first alternative");
    ok($parser->parse('b'), "accepts 'b' via second alternative");
    ok(!$parser->parse('c'), "rejects 'c' (not in alternatives)");
    ok(!$parser->parse('ab'), "rejects 'ab' (only one alternative)");
}

# Test 8: Simple BNF rule without quantifiers
# Rule ::= Identifier /::=/ Identifier /;/
{
    my $test_grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Rule')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Rule',
            expressions => [[
                reference('Identifier'),
                terminal('::='),
                reference('Identifier'),
                terminal(';'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Identifier',
            expressions => [[terminal('[A-Za-z_][A-Za-z_0-9]*')]],
        ),
    ];

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $test_grammar,
        semiring => $semiring,
    );

    ok($parser->parse('Foo::=Bar;'), "accepts 'Foo::=Bar;' as simple Rule");
    ok($parser->parse('Element::=Atom;'), "accepts 'Element::=Atom;' as Rule");
    ok(!$parser->parse('Foo::=;'), "rejects 'Foo::=;' (missing RHS)");
    ok(!$parser->parse('::=Bar;'), "rejects '::=Bar;' (missing LHS)");
    ok(!$parser->parse('Foo::=Bar'), "rejects 'Foo::=Bar' (missing semicolon)");
}

# Test 9: Invalid inputs should be rejected
{
    my $test_grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Identifier')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Identifier',
            expressions => [[terminal('[A-Za-z_][A-Za-z_0-9]*')]],
        ),
    ];

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $test_grammar,
        semiring => $semiring,
    );

    ok(!$parser->parse(''), "rejects empty string");
    ok(!$parser->parse('123'), "rejects string starting with digit");
    ok(!$parser->parse('::='), "rejects punctuation");
}

# Test 10: Multi-symbol sequence with real BNF fragments
# Simplified Rule ::= Identifier /ws/ /::=/ /ws/ Identifier /ws/ /;/
{
    my $test_grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Rule')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Rule',
            expressions => [[
                reference('Identifier'),
                terminal('\\s+'),
                terminal('::='),
                terminal('\\s+'),
                reference('Identifier'),
                terminal('\\s+'),
                terminal(';'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Identifier',
            expressions => [[terminal('[A-Za-z_][A-Za-z_0-9]*')]],
        ),
    ];

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $test_grammar,
        semiring => $semiring,
    );

    ok($parser->parse('Foo ::= Bar ;'), "accepts 'Foo ::= Bar ;' with whitespace");
    ok($parser->parse('Element ::= Atom ;'), "accepts 'Element ::= Atom ;'");
    ok(!$parser->parse('Foo::=Bar;'), "rejects 'Foo::=Bar;' (missing required whitespace)");
}

# Test with full BNF meta-grammar including quantifiers (desugared)
{
    my $desugared = desugar_grammar($grammar);

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $semiring,
    );

    # Simple rule: Identifier ::= /[A-Za-z]+/ ;
    my $input1 = 'Identifier ::= /[A-Za-z]+/ ;';
    ok($parser->parse($input1), "accepts simple rule: $input1");

    # Rule with alternatives
    my $input2 = 'Atom ::= Identifier | InlineRegex ;';
    ok($parser->parse($input2), "accepts rule with alternatives: $input2");

    # Multi-rule input (exercises Rule_plus desugaring)
    my $input3 = q{Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/ ;
Atom ::= Identifier | InlineRegex ;};
    ok($parser->parse($input3), "accepts multi-rule BNF input");
}

done_testing();
