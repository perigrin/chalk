# ABOUTME: Tests for parser→semantic boundary - extracting semantic values from parse results.
# ABOUTME: Documents the gap between parse() boolean return and need for semantic Context extraction.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Context;

# Helper to build test symbols
sub build_symbol {
    my ($type, $value) = @_;
    return bless {
        _type => $type,
        _value => $value,
    }, 'TestSymbol';
}

package TestSymbol {
    use 5.42.0;
    sub type { $_[0]->{_type} }
    sub value { $_[0]->{_value} }
    sub is_reference { $_[0]->{_type} eq 'reference' }
    sub is_terminal { $_[0]->{_type} eq 'terminal' }
    sub is_quantified { false }
    sub goto_key { ($_[0]->{_type} eq 'reference' ? 'n:' : 't:') . $_[0]->{_value} }
}

package TestRule {
    use 5.42.0;
    sub new {
        my ($class, %args) = @_;
        return bless \%args, $class;
    }
    sub name { $_[0]->{name} }
    sub expressions { $_[0]->{expressions} }
}

package main;

# Build simple test grammar: Start ::= /[A-Z]+/
my $grammar = [
    TestRule->new(
        name => 'Start',
        expressions => [
            [ build_symbol('terminal', '[A-Z]+') ]
        ],
    ),
];

my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
my $comp_sr = Chalk::Bootstrap::Semiring::FilterComposite->new(
    semirings => [$bool_sr, $sem_sr],
);

my $parser = Chalk::Bootstrap::Earley->new(
    grammar => $grammar,
    semiring => $comp_sr,
);

# Test 1: parse() returns boolean (current behavior)
{
    my $result = $parser->parse('ABC');
    is(ref($result), '', 'parse() returns scalar boolean');
    ok($result, 'parse() returns true for valid input');
}

{
    my $result = $parser->parse('abc');
    is(ref($result), '', 'parse() returns scalar boolean for invalid input');
    ok(!$result, 'parse() returns false for invalid input');
}

# Test 2: parse_value() returns raw semiring value
{
    my $result = $parser->parse_value('ABC');

    is(ref($result), 'ARRAY', 'parse_value() returns arrayref (composite semiring value)');
    is(scalar($result->@*), 2, 'composite value is 2-tuple [bool, context]');

    my ($bool_val, $context_val) = $result->@*;
    ok($bool_val, 'boolean component is true for valid input');
    isa_ok($context_val, 'Chalk::Bootstrap::Context', 'semantic component is Context');
}

# Test 3: Extracting semantic value from composite result
{
    my $result = $parser->parse_value('ABC');
    my ($bool_val, $context) = $result->@*;

    # The context should contain the parse tree structure
    isa_ok($context, 'Chalk::Bootstrap::Context', 'can extract Context from parse result');

    is($context->rule(), 'Start', 'context has correct rule name');
}

# Test 4: parse_value() returns undef for parse failure
{
    my $result = $parser->parse_value('abc');

    ok(!defined($result), 'parse_value() returns undef for parse failure');
}

done_testing();
