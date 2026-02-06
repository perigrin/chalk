# ABOUTME: Progressive validation test tracking bootstrap compiler progress across phases.
# ABOUTME: Tests each phase independently to identify exactly where implementation is complete.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

# Phase 0: Data model and infrastructure
{
    # Test that core classes load
    use_ok('Chalk::Grammar::Rule');
    use_ok('Chalk::Grammar::Symbol');
    use_ok('Chalk::Grammar::BNF');

    # Test that BNF grammar loads
    my $grammar = Chalk::Grammar::BNF::grammar();
    isa_ok($grammar, 'ARRAY', 'BNF::grammar() returns arrayref');
    is(scalar($grammar->@*), 10, 'BNF meta-grammar has 10 rules');
    isa_ok($grammar->[0], 'Chalk::Grammar::Rule', 'first element is Rule object');
}

# Phase 1a: Earley parser with Boolean semiring
{
    use_ok('Chalk::Bootstrap::Earley');
    use_ok('Chalk::Bootstrap::Semiring::Boolean');

    # Build simple grammar: Start ::= /[A-Z]+/
    my $grammar = [
        TestRule->new(
            name => 'Start',
            expressions => [
                [ TestSymbol->new(type => 'terminal', value => '[A-Z]+') ]
            ],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ABC'), 'Phase 1a: Boolean parser accepts valid input');
    ok(!$parser->parse('abc'), 'Phase 1a: Boolean parser rejects invalid input');
}

# Phase 2a: IR nodes can be constructed manually
{
    use_ok('Chalk::Bootstrap::IR::NodeFactory');
    use_ok('Chalk::Bootstrap::IR::Node::Constant');
    use_ok('Chalk::Bootstrap::IR::Node::MakeSymbol');
    use_ok('Chalk::Bootstrap::IR::Node::MakeRule');

    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    my $const = $factory->make('Constant', const_type => 'string', value => 'test_value');
    isa_ok($const, 'Chalk::Bootstrap::IR::Node::Constant', 'Phase 2a: Can create Constant node');
    is($const->value(), 'test_value', 'Phase 2a: Constant node holds value');
}

# Phase 2b: Semantic actions produce correct IR
{
    use_ok('Chalk::Bootstrap::Semiring::Composite');
    use_ok('Chalk::Bootstrap::Semiring::SemanticAction');
    use_ok('Chalk::Grammar::BNF::Actions');
    use_ok('Chalk::Bootstrap::Context');

    # Test calling semantic action directly with constructed Context
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => 'TestIdentifier',
        children => [],
        position => 0,
        rule => 'Identifier',
    );

    my $result = Chalk::Grammar::BNF::Actions::Identifier($ctx);
    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'Phase 2b: Identifier returns IR node');
    is($result->value(), 'TestIdentifier', 'Phase 2b: action preserves identifier value');

    # Test parser with composite semiring extracts semantic value
    my $grammar = [
        TestRule->new(
            name => 'Start',
            expressions => [
                [ TestSymbol->new(type => 'terminal', value => '[A-Z]+') ]
            ],
        ),
    ];

    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new();
    my $comp_sr = Chalk::Bootstrap::Semiring::Composite->new(
        boolean => $bool_sr,
        semantic => $sem_sr,
    );

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar => $grammar,
        semiring => $comp_sr,
    );

    my $value = $parser->parse_value('ABC');
    ok(defined($value), 'Phase 2b: parse_value() returns defined value for valid input');

    if (defined $value) {
        is(ref($value), 'ARRAY', 'Phase 2b: composite value is arrayref');
        my ($bool_val, $context_val) = $value->@*;
        ok($bool_val, 'Phase 2b: boolean component is true');
        isa_ok($context_val, 'Chalk::Bootstrap::Context', 'Phase 2b: semantic component is Context');
    }
}

# Phase 3: Code generation
TODO: {
    local $TODO = "Phase 3: Code generation not yet implemented";

    # This test will verify that the bootstrap compiler can:
    # 1. Parse the BNF meta-grammar
    # 2. Generate Perl code for a BNF recognizer
    # 3. The generated code accepts/rejects the same inputs as the hand-written version

    fail("Code generation not implemented");
}

# Helper test classes
package TestSymbol {
    use 5.42.0;
    use feature 'class';
    no warnings 'experimental::class';

    class TestSymbol {
        field $type :param :reader;
        field $value :param :reader;

        method is_reference() {
            return $type eq 'reference';
        }

        method is_terminal() {
            return $type eq 'terminal';
        }
    }
}

package TestRule {
    use 5.42.0;
    use feature 'class';
    no warnings 'experimental::class';

    class TestRule {
        field $name :param :reader;
        field $expressions :param :reader;
    }
}

done_testing();
