# ABOUTME: Integration test for Earley parser with semantic actions building IR
# ABOUTME: Verifies parser can build IR graphs from simple grammar inputs
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Grammar::BNF::Actions;
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory for clean test environment
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Build simple grammar for testing: Identifier ::= /[A-Z]+/
# We'll use a simplified grammar since full BNF is complex
my $identifier_rule = {
    name => 'Identifier',
    expressions => [
        [
            { type => 'terminal', value => '/[A-Z]+/' }
        ]
    ],
};

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

# Test 1: Parser with composite semiring accepts valid input
{
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

    my $result = $parser->parse('ABC');

    ok($result, 'composite parser accepts valid input');
}

# Test 2: Parser with composite semiring rejects invalid input
{
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

    my $result = $parser->parse('abc');

    ok(!$result, 'composite parser rejects invalid input');
}

# Test 3: Verify semantic actions are called (manual test)
{
    # This test verifies the semantic action interface works
    # We manually create a context and call actions

    my $actions = Chalk::Grammar::BNF::Actions->new();
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => 'TestId',
        children => [],
        position => 0,
        rule => 'Identifier',
    );

    my $result = $actions->Identifier($ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'semantic action returns IR node');
    is($result->value(), 'TestId', 'semantic action preserves value');
}

done_testing();
