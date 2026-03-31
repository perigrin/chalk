# ABOUTME: Tests Ruby Slippers error recovery — virtual delimiter insertion.
# ABOUTME: Validates that mismatched/missing delimiters trigger virtual token insertion.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Desugar;
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;

sub terminal($v) { Chalk::Grammar::Symbol->new(type => 'terminal', value => $v) }
sub reference($v) { Chalk::Grammar::Symbol->new(type => 'reference', value => $v) }

# Grammar: S ::= '(' E ')' | '{' E '}'
#          E ::= /[a-z]+/
my @rules = (
    Chalk::Grammar::Rule->new(
        name        => 'S',
        expressions => [
            [terminal('\('), reference('E'), terminal('\)')],
            [terminal('\{'), reference('E'), terminal('\}')],
        ],
    ),
    Chalk::Grammar::Rule->new(
        name        => 'E',
        expressions => [[terminal('[a-z]+')]],
    ),
);

my $grammar = Chalk::Bootstrap::Desugar::desugar_grammar(\@rules);
my $bool = Chalk::Bootstrap::Semiring::Boolean->new();

# === Test 1: Valid inputs parse cleanly ===
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar, semiring => $bool, recover => true,
    );
    ok($parser->parse('(hello)'), 'valid parens: (hello) parses');
    is(scalar $parser->errors()->@*, 0, 'valid parens: no errors');
}
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar, semiring => $bool, recover => true,
    );
    ok($parser->parse('{hello}'), 'valid braces: {hello} parses');
    is(scalar $parser->errors()->@*, 0, 'valid braces: no errors');
}

# === Test 2: Missing close paren at end of input ===
# Parser expects ')' but input ends — Ruby Slippers inserts virtual ')'
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar, semiring => $bool, recover => true,
    );
    my $result = $parser->parse('(hello');
    my $errors = $parser->errors();
    ok($result, 'missing close paren: recovered via Ruby Slippers');
    ok($errors->@* > 0, 'missing close paren: error recorded');
    is($errors->[0]{recovery_type}, 'ruby_slippers',
        'missing close paren: recovery type is ruby_slippers');
}

# === Test 3: Mismatched delimiter — ')' expected but '}' found ===
# Parser expects ')' but sees '}' — Ruby Slippers inserts virtual ')'
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar, semiring => $bool, recover => true,
    );
    my $result = $parser->parse('(hello}');
    my $errors = $parser->errors();
    ok($result, 'mismatched delimiters: recovered via Ruby Slippers');
    ok($errors->@* > 0, 'mismatched delimiters: error recorded');
    is($errors->[0]{recovery_type}, 'ruby_slippers',
        'mismatched delimiters: recovery type is ruby_slippers');
}

# === Test 4: Recovery disabled — should fail normally ===
{
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar, semiring => $bool,
    );
    ok(!$parser->parse('(hello'), 'recovery off: missing paren fails');
}

done_testing();
