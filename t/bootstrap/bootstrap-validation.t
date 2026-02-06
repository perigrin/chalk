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
    use Chalk::Bootstrap::Desugar qw(desugar_grammar);
    use Chalk::Bootstrap::Target::Perl;

    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    # Build full pipeline
    my $grammar = Chalk::Grammar::BNF::grammar();
    my $desugared = desugar_grammar($grammar);

    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $actions = Chalk::Grammar::BNF::Actions->new();
    my $sem_sr = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );
    my $comp_sr = Chalk::Bootstrap::Semiring::Composite->new(
        boolean  => $bool_sr,
        semantic => $sem_sr,
    );

    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $comp_sr,
    );

    # Parse the 10-rule BNF meta-grammar
    my $bnf_text = <<'BNF';
Grammar ::= /(?:\s|#[^\n]*)*/ Rule+ ;
Rule ::= Identifier /(?:\s|#[^\n]*)*/ /::=/ /(?:\s|#[^\n]*)*/ Alternatives /(?:\s|#[^\n]*)*/ /;/ /(?:\s|#[^\n]*)*/ ;
Alternatives ::= Sequence /(?:\s|#[^\n]*)*/ /\|/ /(?:\s|#[^\n]*)*/ Alternatives | Sequence ;
Sequence ::= Element /(?:\s|#[^\n]*)+/ Sequence | Element ;
Element ::= Atom Quantifier? ;
Atom ::= Identifier | InlineRegex ;
Quantifier ::= /\*/ | /\+/ | /\?/ ;
Comment ::= /#[^\n]*/ ;
Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/ ;
InlineRegex ::= /\/(?:[^\/\\]|\\.)*\// ;
BNF

    my $result = $parser->parse_value($bnf_text);
    ok(defined $result, 'Phase 3: BNF meta-grammar parses');

    my ($bool_val, $context) = $result->@*;
    ok($bool_val, 'Phase 3: parse is recognized');

    my $ir = $context->extract();
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

    # Structural comparison of each rule
    my $all_match = true;
    for my $i (0 .. $#{$ref_grammar}) {
        my $gen = $gen_grammar->[$i];
        my $ref = $ref_grammar->[$i];
        if ($gen->name() ne $ref->name()) {
            $all_match = false;
            last;
        }
        if ($gen->alternative_count() != $ref->alternative_count()) {
            $all_match = false;
            last;
        }
        for my $j (0 .. $#{$ref->expressions()}) {
            my $gen_alt = $gen->expressions()->[$j];
            my $ref_alt = $ref->expressions()->[$j];
            if (scalar($gen_alt->@*) != scalar($ref_alt->@*)) {
                $all_match = false;
                last;
            }
            for my $k (0 .. $#{$ref_alt}) {
                my $gs = $gen_alt->[$k];
                my $rs = $ref_alt->[$k];
                if ($gs->type() ne $rs->type()
                    || $gs->value() ne $rs->value()
                    || ($gs->quantifier() // '') ne ($rs->quantifier() // '')) {
                    $all_match = false;
                    last;
                }
            }
        }
    }
    ok($all_match, 'Phase 3: generated grammar structurally matches hand-written grammar');

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
