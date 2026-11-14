# ABOUTME: Integration test for Phase 2b - parsing BNF text produces IR nodes.
# ABOUTME: Validates the full pipeline: BNF text → Earley parse → semantic actions → IR.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(build_parser parse_ir);
use Chalk::IR::NodeFactory;

# Reset factory for clean test state

my $parser = build_parser();

# The parse yields Chalk::Grammar::Rule / Chalk::Grammar::Symbol objects
# (c90b95f0 replaced the Constructor:Rule/Expression/Symbol nodes): a Rule
# has a name and expressions, an arrayref of alternatives, each an arrayref
# of Symbols (type terminal|reference, value).

# Test 1: Parse simple identifier-only rule
{
    my $input = "Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/ ;";
    my $ir = parse_ir($parser, $input);

    ok(defined $ir, 'parse single rule returns defined IR');
    isa_ok($ir, 'ARRAY', 'Grammar action returns arrayref');

    is(scalar($ir->@*), 1, 'single rule produces 1 Rule');
    my $rule = $ir->[0];
    isa_ok($rule, 'Chalk::Grammar::Rule');
    is($rule->name, 'Identifier', 'rule name is "Identifier"');

    my $exprs = $rule->expressions;
    isa_ok($exprs, 'ARRAY', 'expressions is arrayref');
    is(scalar($exprs->@*), 1, 'rule has 1 alternative');

    my $elements = $exprs->[0];
    is(scalar($elements->@*), 1, 'expression has 1 element');
    isa_ok($elements->[0], 'Chalk::Grammar::Symbol');
    ok($elements->[0]->is_terminal, 'element type is terminal');
}

# Test 2: Parse rule with alternatives
{
    my $input = "Atom ::= Identifier | InlineRegex ;";
    my $ir = parse_ir($parser, $input);

    ok(defined $ir, 'parse rule with alternatives returns defined IR');
    is(scalar($ir->@*), 1, 'single rule produces 1 Rule');
    my $rule = $ir->[0];
    is($rule->name, 'Atom', 'rule name is "Atom"');

    my $exprs = $rule->expressions;
    is(scalar($exprs->@*), 2, 'rule has 2 alternatives');
    is(scalar($exprs->[0]->@*), 1, 'first alternative has 1 element');
    ok($exprs->[0][0]->is_reference, 'first alt element is reference');
    is(scalar($exprs->[1]->@*), 1, 'second alternative has 1 element');
    ok($exprs->[1][0]->is_reference, 'second alt element is reference');
}

# Test 3: Parse rule with sequence of elements
{
    my $input = "Rule ::= Identifier /::=/ Alternatives /;/ ;";
    my $ir = parse_ir($parser, $input);

    ok(defined $ir, 'parse rule with sequence returns defined IR');
    is(scalar($ir->@*), 1, 'single rule produces 1 Rule');
    my $rule = $ir->[0];
    is($rule->name, 'Rule', 'rule name is "Rule"');

    my $exprs = $rule->expressions;
    is(scalar($exprs->@*), 1, 'rule has 1 alternative');
    my $elements = $exprs->[0];
    is(scalar($elements->@*), 4, 'sequence has 4 elements');

    ok($elements->[0]->is_reference, 'element 1 is reference');
    is($elements->[0]->value, 'Identifier', 'element 1 is Identifier');
    ok($elements->[1]->is_terminal, 'element 2 is terminal');
    ok($elements->[2]->is_reference, 'element 3 is reference');
    ok($elements->[3]->is_terminal, 'element 4 is terminal');
}

# Test 4: Parse multiple rules
{
    my $input = "Identifier ::= /[A-Za-z]+/ ; Comment ::= /#[^\\n]*/ ;";
    my $ir = parse_ir($parser, $input);

    ok(defined $ir, 'parse multiple rules returns defined IR');
    is(scalar($ir->@*), 2, 'two rules produce 2 Rule nodes');
    is($ir->[0]->name, 'Identifier', 'first rule is Identifier');
    is($ir->[1]->name, 'Comment', 'second rule is Comment');
}
# Test 5: Invalid input returns undef
{
    my $ir = parse_ir($parser, 'not valid BNF at all');
    ok(!defined($ir), 'invalid input returns undef');
}

done_testing();
