# ABOUTME: Tests for Earley parser nullable nonterminal prediction fix.
# ABOUTME: Exercises _advance_from_completed for repeated nullable symbols in rules.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

# Helper to create terminal symbol
sub terminal($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => $value,
    );
}

# Helper to create reference symbol (nonterminal)
sub reference($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'reference',
        value => $value,
    );
}

sub make_parser($grammar) {
    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    return Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );
}

# Test 1: Same nullable nonterminal appears twice in a rule
# This is the exact pattern that motivated _advance_from_completed:
# S ::= N "a" N  where N ::= (epsilon)
# The second N prediction is suppressed because N was already predicted
# at that position. _advance_from_completed must handle this.
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name => 'S',
            expressions => [[
                reference('N'), terminal('a'), reference('N'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name => 'N',
            expressions => [
                [],  # epsilon
            ],
        ),
    ];

    my $parser = make_parser($grammar);

    ok($parser->parse('a'),   'two nullable: accepts "a" (both N match epsilon)');
    ok(!$parser->parse(''),   'two nullable: rejects empty (terminal "a" required)');
    ok(!$parser->parse('aa'), 'two nullable: rejects "aa" (only one terminal)');
}

# Test 2: Nullable nonterminal with optional content
# S ::= N "x" N  where N ::= "n" | (epsilon)
# N can match "n" or nothing
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name => 'S',
            expressions => [[
                reference('N'), terminal('x'), reference('N'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name => 'N',
            expressions => [
                [terminal('n')],
                [],  # epsilon
            ],
        ),
    ];

    my $parser = make_parser($grammar);

    ok($parser->parse('x'),    'nullable-or-content: accepts "x" (both N empty)');
    ok($parser->parse('nx'),   'nullable-or-content: accepts "nx" (first N matches)');
    ok($parser->parse('xn'),   'nullable-or-content: accepts "xn" (second N matches)');
    ok($parser->parse('nxn'),  'nullable-or-content: accepts "nxn" (both N match)');
    ok(!$parser->parse(''),    'nullable-or-content: rejects empty');
    ok(!$parser->parse('nn'),  'nullable-or-content: rejects "nn" (no terminal x)');
    ok(!$parser->parse('nxnn'),'nullable-or-content: rejects "nxnn"');
}

# Test 3: Three nullable nonterminals in a rule
# S ::= N "a" N "b" N  where N ::= (epsilon)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name => 'S',
            expressions => [[
                reference('N'), terminal('a'),
                reference('N'), terminal('b'),
                reference('N'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name => 'N',
            expressions => [
                [],  # epsilon
            ],
        ),
    ];

    my $parser = make_parser($grammar);

    ok($parser->parse('ab'),   'three nullable: accepts "ab"');
    ok(!$parser->parse('a'),   'three nullable: rejects "a" (missing b)');
    ok(!$parser->parse('b'),   'three nullable: rejects "b" (missing a)');
    ok(!$parser->parse(''),    'three nullable: rejects empty');
    ok(!$parser->parse('ba'),  'three nullable: rejects "ba" (wrong order)');
}

# Test 4: Nullable at start only
# S ::= N "x"  where N ::= (epsilon)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name => 'S',
            expressions => [[
                reference('N'), terminal('x'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name => 'N',
            expressions => [[]],
        ),
    ];

    my $parser = make_parser($grammar);

    ok($parser->parse('x'),  'nullable at start: accepts "x"');
    ok(!$parser->parse(''),  'nullable at start: rejects empty');
}

# Test 5: Nullable at end only
# S ::= "x" N  where N ::= (epsilon)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name => 'S',
            expressions => [[
                terminal('x'), reference('N'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name => 'N',
            expressions => [[]],
        ),
    ];

    my $parser = make_parser($grammar);

    ok($parser->parse('x'),  'nullable at end: accepts "x"');
    ok(!$parser->parse(''),  'nullable at end: rejects empty');
}

# Test 6: Mirrors the real grammar pattern: Program ::= _ StatementList? _
# where _ is nullable whitespace
# S ::= WS Content WS  where WS ::= /\s*/ (nullable), Content ::= "x"
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name => 'S',
            expressions => [[
                reference('WS'), reference('Content'), reference('WS'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name => 'WS',
            expressions => [
                [terminal(q{(?:\s|#[^\n]*)*})],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name => 'Content',
            expressions => [
                [terminal('[a-z]+')],
            ],
        ),
    ];

    my $parser = make_parser($grammar);

    ok($parser->parse('foo'),      'real pattern: accepts "foo" (no whitespace)');
    ok($parser->parse(' foo'),     'real pattern: accepts " foo" (leading ws)');
    ok($parser->parse('foo '),     'real pattern: accepts "foo " (trailing ws)');
    ok($parser->parse(' foo '),    'real pattern: accepts " foo " (both ws)');
    ok($parser->parse("# c\nfoo"), 'real pattern: accepts comment before content');
    ok(!$parser->parse(''),        'real pattern: rejects empty (Content required)');
}

# Test 7: Chain of epsilon-only nonterminals
# S ::= A B "x"  where A ::= (epsilon), B ::= (epsilon)
# Different nullable rules, not the same one repeated
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name => 'S',
            expressions => [[
                reference('A'), reference('B'), terminal('x'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name => 'A',
            expressions => [[]],
        ),
        Chalk::Grammar::Rule->new(
            name => 'B',
            expressions => [[]],
        ),
    ];

    my $parser = make_parser($grammar);

    ok($parser->parse('x'),   'epsilon chain: accepts "x" (A and B both empty)');
    ok(!$parser->parse(''),   'epsilon chain: rejects empty');
    ok(!$parser->parse('xx'), 'epsilon chain: rejects "xx"');
}

# Test 8: Nullable with desugared quantifier pattern (X_opt ::= X | epsilon)
# S ::= "a" X_opt "b"  where X_opt ::= "x" | (epsilon)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name => 'S',
            expressions => [[
                terminal('a'), reference('X_opt'), terminal('b'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name => 'X_opt',
            expressions => [
                [terminal('x')],
                [],  # epsilon
            ],
        ),
    ];

    my $parser = make_parser($grammar);

    ok($parser->parse('ab'),   'quantifier opt: accepts "ab" (X_opt empty)');
    ok($parser->parse('axb'),  'quantifier opt: accepts "axb" (X_opt matches)');
    ok(!$parser->parse('a'),   'quantifier opt: rejects "a" (missing b)');
    ok(!$parser->parse('axxb'),'quantifier opt: rejects "axxb" (too many x)');
}

# Test 9: Non-nullable nonterminal should NOT trigger _advance_from_completed
# S ::= A A  where A ::= "x" (not nullable)
# This tests that the fix does not over-apply
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name => 'S',
            expressions => [[
                reference('A'), reference('A'),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name => 'A',
            expressions => [
                [terminal('x')],
            ],
        ),
    ];

    my $parser = make_parser($grammar);

    ok($parser->parse('xx'),   'non-nullable: accepts "xx"');
    ok(!$parser->parse('x'),   'non-nullable: rejects "x" (need two A)');
    ok(!$parser->parse('xxx'), 'non-nullable: rejects "xxx"');
    ok(!$parser->parse(''),    'non-nullable: rejects empty');
}

done_testing();
