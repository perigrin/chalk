# ABOUTME: Tests semantic actions with multiple values (multiple rules, alternatives, expressions)
# ABOUTME: Verifies that Grammar, Alternatives, and Rule actions handle multi-value scenarios correctly
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::BNF::Actions;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory for clean test environment
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Create Actions instance to use throughout tests
my $actions = Chalk::Grammar::BNF::Actions->new();

# Test 1: Alternatives should return arrayref of ALL alternatives, not just first
{
    # Create 3 MakeExpression nodes
    my $expr1 = $factory->make('MakeExpression', elements => []);
    my $expr2 = $factory->make('MakeExpression', elements => []);
    my $expr3 = $factory->make('MakeExpression', elements => []);

    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $expr1,
        children => [],
        position => 0,
        rule     => 'Sequence',
    );
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $expr2,
        children => [],
        position => 5,
        rule     => 'Sequence',
    );
    my $ctx3 = Chalk::Bootstrap::Context->new(
        focus    => $expr3,
        children => [],
        position => 10,
        rule     => 'Sequence',
    );

    # Alternatives ::= Sequence | Sequence | Sequence
    my $alts_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$ctx1, $ctx2, $ctx3],
        position => 0,
        rule     => 'Alternatives',
    );

    my $result = $actions->Alternatives($alts_ctx);

    # BUG 2: Currently returns only first expression, should return arrayref of all 3
    ok(ref($result) eq 'ARRAY', 'Alternatives returns arrayref');
    is(scalar($result->@*), 3, 'Alternatives returns all 3 alternatives');
    isa_ok($result->[0], 'Chalk::Bootstrap::IR::Node::MakeExpression', 'First alternative is MakeExpression');
    isa_ok($result->[1], 'Chalk::Bootstrap::IR::Node::MakeExpression', 'Second alternative is MakeExpression');
    isa_ok($result->[2], 'Chalk::Bootstrap::IR::Node::MakeExpression', 'Third alternative is MakeExpression');
}

# Test 2: Rule should receive arrayref of expressions and pass it correctly
{
    # Create rule name
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'TestRule');
    my $name_ctx = Chalk::Bootstrap::Context->new(
        focus    => $name_const,
        children => [],
        position => 0,
        rule     => 'Identifier',
    );

    # Create 2 alternatives (as arrayref from fixed Alternatives)
    my $expr1 = $factory->make('MakeExpression', elements => []);
    my $expr2 = $factory->make('MakeExpression', elements => []);
    my $alts_arrayref = [$expr1, $expr2];

    my $alts_ctx = Chalk::Bootstrap::Context->new(
        focus    => $alts_arrayref,
        children => [],
        position => 10,
        rule     => 'Alternatives',
    );

    # Rule ::= Identifier ... Alternatives
    my $rule_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$name_ctx, $alts_ctx],
        position => 0,
        rule     => 'Rule',
    );

    my $result = $actions->Rule($rule_ctx);

    # BUG 3: Currently checks for single MakeExpression, should accept arrayref
    isa_ok($result, 'Chalk::Bootstrap::IR::Node::MakeRule', 'Rule creates MakeRule');
    is($result->inputs()->[0]->value(), 'TestRule', 'Rule name is correct');

    # The expressions input should be an arrayref
    my $expressions = $result->inputs()->[1];
    ok(ref($expressions) eq 'ARRAY', 'Rule expressions is arrayref');
    is(scalar($expressions->@*), 2, 'Rule has 2 expressions');
    isa_ok($expressions->[0], 'Chalk::Bootstrap::IR::Node::MakeExpression', 'First expression is MakeExpression');
    isa_ok($expressions->[1], 'Chalk::Bootstrap::IR::Node::MakeExpression', 'Second expression is MakeExpression');
}

# Test 3: Grammar should return arrayref of ALL rules, not just first
{
    # Create 3 MakeRule nodes
    my $name1 = $factory->make('Constant', const_type => 'string', value => 'Rule1');
    my $name2 = $factory->make('Constant', const_type => 'string', value => 'Rule2');
    my $name3 = $factory->make('Constant', const_type => 'string', value => 'Rule3');

    my $expr = $factory->make('MakeExpression', elements => []);

    my $rule1 = $factory->make('MakeRule', name => $name1, expressions => [$expr]);
    my $rule2 = $factory->make('MakeRule', name => $name2, expressions => [$expr]);
    my $rule3 = $factory->make('MakeRule', name => $name3, expressions => [$expr]);

    my $ctx1 = Chalk::Bootstrap::Context->new(
        focus    => $rule1,
        children => [],
        position => 0,
        rule     => 'Rule',
    );
    my $ctx2 = Chalk::Bootstrap::Context->new(
        focus    => $rule2,
        children => [],
        position => 20,
        rule     => 'Rule',
    );
    my $ctx3 = Chalk::Bootstrap::Context->new(
        focus    => $rule3,
        children => [],
        position => 40,
        rule     => 'Rule',
    );

    # Grammar ::= Rule+
    my $grammar_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$ctx1, $ctx2, $ctx3],
        position => 0,
        rule     => 'Grammar',
    );

    my $result = $actions->Grammar($grammar_ctx);

    # BUG 1: Currently returns only first rule, should return arrayref of all 3
    ok(ref($result) eq 'ARRAY', 'Grammar returns arrayref');
    is(scalar($result->@*), 3, 'Grammar returns all 3 rules');
    isa_ok($result->[0], 'Chalk::Bootstrap::IR::Node::MakeRule', 'First rule is MakeRule');
    isa_ok($result->[1], 'Chalk::Bootstrap::IR::Node::MakeRule', 'Second rule is MakeRule');
    isa_ok($result->[2], 'Chalk::Bootstrap::IR::Node::MakeRule', 'Third rule is MakeRule');
    is($result->[0]->inputs()->[0]->value(), 'Rule1', 'First rule name is Rule1');
    is($result->[1]->inputs()->[0]->value(), 'Rule2', 'Second rule name is Rule2');
    is($result->[2]->inputs()->[0]->value(), 'Rule3', 'Third rule name is Rule3');
}

done_testing();
