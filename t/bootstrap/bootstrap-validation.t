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
    use_ok('Chalk::Bootstrap::IR::Node::Constructor');

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
    my $actions = Chalk::Grammar::BNF::Actions->new();
    my $ctx = Chalk::Bootstrap::Context->new(
        focus => 'TestIdentifier',
        children => [],
        position => 0,
        rule => 'Identifier',
    );

    my $result = $actions->Identifier($ctx);
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
{
    use lib 't/bootstrap/lib';
    use TestPipeline qw(full_pipeline optimized_pipeline bnf_text grammars_match);
    use Chalk::Bootstrap::Desugar qw(desugar_grammar);
    use Chalk::Bootstrap::Target::Perl;

    my $ir = full_pipeline();
    ok(defined $ir, 'Phase 3: BNF meta-grammar parses');
    is(scalar($ir->@*), 10, 'Phase 3: IR contains 10 rules');

    # Generate Perl code
    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    ok(defined $generated, 'Phase 3: code generation produces output');

    # Eval the generated code
    eval $generated;
    is($@, '', 'Phase 3: generated code evals without error');

    # Compare generated grammar to hand-written grammar
    my $gen_grammar = Chalk::Grammar::BNF::Generated::grammar();
    my $ref_grammar = Chalk::Grammar::BNF::grammar();

    is(scalar($gen_grammar->@*), scalar($ref_grammar->@*),
        'Phase 3: same number of rules');

    ok(grammars_match($gen_grammar, $ref_grammar),
        'Phase 3: generated grammar structurally matches hand-written grammar');

    # Build parser from generated grammar and verify it accepts/rejects same inputs
    my $gen_desugared = desugar_grammar($gen_grammar);
    my $gen_bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $gen_parser = Chalk::Bootstrap::Earley->new(
        grammar  => $gen_desugared,
        semiring => $gen_bool_sr,
    );

    # Test inputs that the hand-written parser accepts
    ok($gen_parser->parse("Identifier ::= /[A-Za-z]+/ ;"),
        'Phase 3: generated parser accepts simple rule');
    ok($gen_parser->parse("Atom ::= Identifier | InlineRegex ;"),
        'Phase 3: generated parser accepts rule with alternatives');

    # Test inputs that should be rejected
    ok(!$gen_parser->parse("not valid BNF"),
        'Phase 3: generated parser rejects invalid input');
}

# Phase 4: Optimizer preserves correctness
{
    use Chalk::Bootstrap::Optimizer;
    use Chalk::Bootstrap::Optimizer::DCE;
    use Chalk::Bootstrap::IR::NodeFactory;

    my $ir = optimized_pipeline();
    ok(defined $ir, 'Phase 4: optimized pipeline produces IR');
    is(scalar($ir->@*), 10, 'Phase 4: optimized IR contains 10 rules');

    # Generate Perl code from optimized IR
    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    ok(defined $generated, 'Phase 4: optimized code generation produces output');

    # Use a distinct class name to avoid collision with Phase 3's eval
    my $opt_generated = $generated;
    $opt_generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::BNF::Optimized/g;
    eval $opt_generated;
    is($@, '', 'Phase 4: optimized generated code evals without error');

    # Structural comparison with hand-written grammar
    my $gen_grammar = Chalk::Grammar::BNF::Optimized::grammar();
    my $ref_grammar = Chalk::Grammar::BNF::grammar();

    is(scalar($gen_grammar->@*), scalar($ref_grammar->@*),
        'Phase 4: same number of rules after optimization');
    ok(grammars_match($gen_grammar, $ref_grammar),
        'Phase 4: optimized grammar structurally matches hand-written grammar');
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
