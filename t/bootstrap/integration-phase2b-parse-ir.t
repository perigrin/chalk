# ABOUTME: Integration test for Phase 2b - parsing BNF text produces IR nodes.
# ABOUTME: Validates the full pipeline: BNF text → Earley parse → semantic actions → IR.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Composite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Grammar::BNF::Actions;
use Chalk::Bootstrap::Desugar qw(desugar_grammar);
use Chalk::Grammar::BNF;
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory for clean test state
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

# Build the full parse pipeline
sub build_parser {
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

    return Chalk::Bootstrap::Earley->new(
        grammar  => $desugared,
        semiring => $comp_sr,
    );
}

# Helper to extract semantic value from parse result
sub parse_ir {
    my ($parser, $input) = @_;
    my $result = $parser->parse_value($input);
    return undef unless defined $result;
    my ($bool_val, $context) = $result->@*;
    return undef unless $bool_val;
    return $context->extract();
}

my $parser = build_parser();

# Test 1: Parse simple identifier-only rule
{
    my $input = "Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/ ;";
    my $ir = parse_ir($parser, $input);

    ok(defined $ir, 'parse single rule returns defined IR');
    isa_ok($ir, 'ARRAY', 'Grammar action returns arrayref');

    # Grammar produces arrayref of Rule nodes
    is(scalar($ir->@*), 1, 'single rule produces 1 Rule');
    my $rule = $ir->[0];
    isa_ok($rule, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($rule->class(), 'Rule', 'element is Rule');

    # Check rule name
    my $name = $rule->inputs()->[0];
    isa_ok($name, 'Chalk::Bootstrap::IR::Node::Constant', 'rule name is Constant');
    is($name->value(), 'Identifier', 'rule name is "Identifier"');

    # Check expressions
    my $exprs = $rule->inputs()->[1];
    isa_ok($exprs, 'ARRAY', 'expressions is arrayref');
    is(scalar($exprs->@*), 1, 'rule has 1 alternative');

    my $expr = $exprs->[0];
    isa_ok($expr, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($expr->class(), 'Expression', 'alternative is Expression');

    # The expression should have 1 element (the InlineRegex terminal)
    my $elements = $expr->inputs()->[0];
    is(scalar($elements->@*), 1, 'expression has 1 element');

    my $elem = $elements->[0];
    isa_ok($elem, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($elem->class(), 'Symbol', 'element is Symbol');
    is($elem->inputs()->[0]->value(), 'terminal', 'element type is terminal');
}

# Test 2: Parse rule with alternatives
{
    my $input = "Atom ::= Identifier | InlineRegex ;";
    my $ir = parse_ir($parser, $input);

    ok(defined $ir, 'parse rule with alternatives returns defined IR');
    is(scalar($ir->@*), 1, 'single rule produces 1 Rule');
    my $rule = $ir->[0];

    is($rule->inputs()->[0]->value(), 'Atom', 'rule name is "Atom"');

    my $exprs = $rule->inputs()->[1];
    is(scalar($exprs->@*), 2, 'rule has 2 alternatives');

    # First alternative: Identifier (reference)
    my $alt1_elements = $exprs->[0]->inputs()->[0];
    is(scalar($alt1_elements->@*), 1, 'first alternative has 1 element');
    is($alt1_elements->[0]->inputs()->[0]->value(), 'reference', 'first alt element is reference');

    # Second alternative: InlineRegex (reference to InlineRegex rule)
    my $alt2_elements = $exprs->[1]->inputs()->[0];
    is(scalar($alt2_elements->@*), 1, 'second alternative has 1 element');
    is($alt2_elements->[0]->inputs()->[0]->value(), 'reference', 'second alt element is reference');
}

# Test 3: Parse rule with sequence of elements
{
    my $input = "Rule ::= Identifier /::=/ Alternatives /;/ ;";
    my $ir = parse_ir($parser, $input);

    ok(defined $ir, 'parse rule with sequence returns defined IR');
    is(scalar($ir->@*), 1, 'single rule produces 1 Rule');
    my $rule = $ir->[0];

    is($rule->inputs()->[0]->value(), 'Rule', 'rule name is "Rule"');

    my $exprs = $rule->inputs()->[1];
    is(scalar($exprs->@*), 1, 'rule has 1 alternative');

    my $elements = $exprs->[0]->inputs()->[0];
    is(scalar($elements->@*), 4, 'sequence has 4 elements');

    # Verify element types in order
    is($elements->[0]->inputs()->[0]->value(), 'reference', 'element 1 is reference');
    is($elements->[0]->inputs()->[1]->value(), 'Identifier', 'element 1 is Identifier');
    is($elements->[1]->inputs()->[0]->value(), 'terminal', 'element 2 is terminal');
    is($elements->[2]->inputs()->[0]->value(), 'reference', 'element 3 is reference');
    is($elements->[3]->inputs()->[0]->value(), 'terminal', 'element 4 is terminal');
}

# Test 4: Parse multiple rules
{
    my $input = "Identifier ::= /[A-Za-z]+/ ; Comment ::= /#[^\\n]*/ ;";
    my $ir = parse_ir($parser, $input);

    ok(defined $ir, 'parse multiple rules returns defined IR');
    is(scalar($ir->@*), 2, 'two rules produce 2 Rule nodes');
    is($ir->[0]->inputs()->[0]->value(), 'Identifier', 'first rule is Identifier');
    is($ir->[1]->inputs()->[0]->value(), 'Comment', 'second rule is Comment');
}

# Test 5: Invalid input returns undef
{
    my $ir = parse_ir($parser, 'not valid BNF at all');
    ok(!defined($ir), 'invalid input returns undef');
}

done_testing();
