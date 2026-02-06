# ABOUTME: Tests for Chalk::Bootstrap::Earley with regex terminal patterns.
# ABOUTME: Layer 3: Validates pattern matching for BNF meta-grammar terminals.
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

# Test 1: Identifier pattern from BNF meta-grammar
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('[A-Za-z_][A-Za-z_0-9]*')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('Identifier'), "accepts 'Identifier'");
    ok($parser->parse('Rule_Name'), "accepts 'Rule_Name'");
    ok($parser->parse('x'), "accepts single letter 'x'");
    ok($parser->parse('_private'), "accepts leading underscore");
    ok($parser->parse('var123'), "accepts with numbers");
    ok(!$parser->parse('123var'), "rejects leading digit");
    ok(!$parser->parse(''), "rejects empty string");
}

# Test 2: Whitespace pattern (common in BNF)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('\s+')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse(' '), "accepts single space");
    ok($parser->parse('   '), "accepts multiple spaces");
    ok($parser->parse("\t"), "accepts tab");
    ok($parser->parse("\n"), "accepts newline");
    ok($parser->parse("  \t\n  "), "accepts mixed whitespace");
    ok(!$parser->parse(''), "rejects empty string");
    ok(!$parser->parse('a'), "rejects non-whitespace");
}

# Test 3: Comment pattern from BNF meta-grammar
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('#[^\n]*')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('# comment'), "accepts comment");
    ok($parser->parse('#'), "accepts bare #");
    ok($parser->parse('# with spaces and symbols !@#$%'), "accepts complex comment");
    ok(!$parser->parse("# line\nnext"), "rejects across newline");
    ok(!$parser->parse('comment'), "rejects without #");
}

# Test 4: Whitespace/comment combo pattern from BNF meta-grammar
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('(?:\s|#[^\n]*)*')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    # TODO: Zero-width matches need special handling in scan
    TODO: {
        local $TODO = "Zero-width terminal matches not yet supported";
        ok($parser->parse(''), "accepts empty (zero-width match)");
    }
    ok($parser->parse(' '), "accepts space");
    ok($parser->parse('# comment'), "accepts comment");
    ok($parser->parse("  # comment\n  "), "accepts mixed ws and comment");
    ok($parser->parse("# first\n# second"), "accepts multiple comments");
    ok($parser->parse("   \t\n  # comment\n   "), "accepts complex mix");
}

# Test 5: Inline regex pattern from BNF meta-grammar
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('/(?:[^/\\\\]|\\\\.)*/')]] ,
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('//'), "accepts empty regex");
    ok($parser->parse('/a/'), "accepts simple regex");
    ok($parser->parse('/[a-z]+/'), "accepts character class");
    ok($parser->parse('/\\/escaped slash/'), "accepts escaped slash");
    ok($parser->parse('/\\d+/'), "accepts escaped d");
    ok(!$parser->parse('/unclosed'), "rejects unclosed regex");
}

# Test 6: Sequence with whitespace (simplified BNF rule structure)
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[
                reference('Identifier'),
                terminal('(?:\s|#[^\n]*)*'),
                terminal('::='),
            ]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Identifier',
            expressions => [[terminal('[A-Za-z_][A-Za-z_0-9]*')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    # TODO: Zero-width match in middle of sequence
    TODO: {
        local $TODO = "Zero-width terminal matches not yet supported";
        ok($parser->parse('Rule::='), "accepts without whitespace");
    }
    ok($parser->parse('Rule ::='), "accepts with space");
    ok($parser->parse('Rule  ::='), "accepts with multiple spaces");
    ok($parser->parse("Rule\t::="), "accepts with tab");
    ok($parser->parse("Rule # comment\n::="), "accepts with comment");
    ok(!$parser->parse('Rule:='), "rejects missing colon");
}

# Test 7: Number patterns
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('\d+(?:\.\d+)?')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('42'), "accepts integer");
    ok($parser->parse('3.14'), "accepts decimal");
    ok($parser->parse('0'), "accepts zero");
    ok($parser->parse('123.456'), "accepts long decimal");
    ok(!$parser->parse('.5'), "rejects leading dot");
    ok(!$parser->parse('12.'), "rejects trailing dot");
}

# Test 8: Alternative terminals with different patterns
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[reference('Token')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Token',
            expressions => [
                [terminal('[A-Za-z_][A-Za-z_0-9]*')],  # Identifier
                [terminal('\d+')],                      # Number
                [terminal('::=|;|\|')],                 # Operators
            ],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('Identifier'), "accepts identifier");
    ok($parser->parse('123'), "accepts number");
    ok($parser->parse('::='), "accepts ::=");
    ok($parser->parse(';'), "accepts semicolon");
    ok($parser->parse('|'), "accepts pipe");
    ok(!$parser->parse('+'), "rejects unmatched operator");
}

# Test 9: Nested regex groups
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('(?:(?:a|b)+|(?:c|d)+)')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a'), "accepts 'a'");
    ok($parser->parse('aaa'), "accepts 'aaa'");
    ok($parser->parse('ab'), "accepts 'ab'");
    ok($parser->parse('c'), "accepts 'c'");
    ok($parser->parse('cd'), "accepts 'cd'");
    ok(!$parser->parse('ac'), "rejects 'ac' (crosses groups)");
}

# Test 10: Escaped characters in regex
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Start',
            expressions => [[terminal('\( \) \[ \] \{ \}')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('( ) [ ] { }'), "accepts escaped brackets");
    ok(!$parser->parse('()[]{}'), "rejects without spaces");
}

done_testing();
