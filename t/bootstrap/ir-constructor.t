# ABOUTME: Tests for parameterized Constructor IR node replacing MakeSymbol/MakeExpression/MakeRule
# ABOUTME: Verifies Constructor with class parameter works for all three grammar object types
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory to ensure clean test state
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

# Test 1: Constructor:Symbol creation
{
    my $type = $factory->make('Constant',
        const_type => 'enum',
        value => 'terminal'
    );

    my $value = $factory->make('Constant',
        const_type => 'string',
        value => 'foo'
    );

    my $symbol = $factory->make('Constructor',
        class => 'Symbol',
        type => $type,
        value => $value,
        quantifier => undef
    );

    isa_ok($symbol, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($symbol->class(), 'Symbol', 'class attribute is Symbol');
    is($symbol->operation(), 'Constructor', 'operation is Constructor');

    my $inputs = $symbol->inputs();
    is($inputs->[0], $type, 'first input is type');
    is($inputs->[1], $value, 'second input is value');
    is($inputs->[2], undef, 'third input is quantifier (undef)');
}

# Test 2: Constructor:Expression creation
{
    my $elem1 = $factory->make('Constant',
        const_type => 'string',
        value => 'elem1'
    );

    my $elem2 = $factory->make('Constant',
        const_type => 'string',
        value => 'elem2'
    );

    my $expr = $factory->make('Constructor',
        class => 'Expression',
        elements => [$elem1, $elem2]
    );

    isa_ok($expr, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($expr->class(), 'Expression', 'class attribute is Expression');
    is($expr->operation(), 'Constructor', 'operation is Constructor');

    my $inputs = $expr->inputs();
    is(scalar($inputs->[0]->@*), 2, 'elements array has 2 elements');
    is($inputs->[0]->[0], $elem1, 'first element matches');
    is($inputs->[0]->[1], $elem2, 'second element matches');
}

# Test 3: Constructor:Rule creation
{
    my $name = $factory->make('Constant',
        const_type => 'string',
        value => 'MyRule'
    );

    my $expr1 = $factory->make('Constant',
        const_type => 'string',
        value => 'expr1'
    );

    my $expr2 = $factory->make('Constant',
        const_type => 'string',
        value => 'expr2'
    );

    my $rule = $factory->make('Constructor',
        class => 'Rule',
        name => $name,
        expressions => [$expr1, $expr2]
    );

    isa_ok($rule, 'Chalk::Bootstrap::IR::Node::Constructor');
    is($rule->class(), 'Rule', 'class attribute is Rule');
    is($rule->operation(), 'Constructor', 'operation is Constructor');

    my $inputs = $rule->inputs();
    is($inputs->[0], $name, 'first input is name');
    is(scalar($inputs->[1]->@*), 2, 'expressions array has 2 expressions');
    is($inputs->[1]->[0], $expr1, 'first expression matches');
    is($inputs->[1]->[1], $expr2, 'second expression matches');
}

# Test 4: Hash consing - different classes not deduplicated
{
    my $const1 = $factory->make('Constant',
        const_type => 'string',
        value => 'shared'
    );

    my $const2 = $factory->make('Constant',
        const_type => 'string',
        value => 'other'
    );

    # Create Constructor:Symbol
    my $symbol = $factory->make('Constructor',
        class => 'Symbol',
        type => $const1,
        value => $const2,
        quantifier => undef
    );

    # Create Constructor:Expression with same constants (different structure)
    my $expr = $factory->make('Constructor',
        class => 'Expression',
        elements => [$const1]
    );

    isnt($symbol, $expr, 'different Constructor classes are different nodes');
    isnt(refaddr($symbol), refaddr($expr), 'reference addresses differ');
}

# Test 5: Hash consing - same class and inputs deduplicated
{
    my $type = $factory->make('Constant',
        const_type => 'enum',
        value => 'reference'
    );

    my $value = $factory->make('Constant',
        const_type => 'string',
        value => 'bar'
    );

    my $symbol1 = $factory->make('Constructor',
        class => 'Symbol',
        type => $type,
        value => $value,
        quantifier => undef
    );

    my $symbol2 = $factory->make('Constructor',
        class => 'Symbol',
        type => $type,
        value => $value,
        quantifier => undef
    );

    is($symbol1, $symbol2, 'identical Constructor:Symbol nodes deduplicated');
    is(refaddr($symbol1), refaddr($symbol2), 'reference addresses match');
}

# Test 6: Hash consing - class attribute distinguishes nodes
{
    my $const = $factory->make('Constant',
        const_type => 'string',
        value => 'test'
    );

    # Two constructors with same input but different class
    my $expr1 = $factory->make('Constructor',
        class => 'Expression',
        elements => [$const]
    );

    my $expr2 = $factory->make('Constructor',
        class => 'Expression',
        elements => [$const]
    );

    my $expr3 = $factory->make('Constructor',
        class => 'Rule',
        name => $const,
        expressions => []
    );

    is($expr1, $expr2, 'same class and inputs deduplicated');
    isnt($expr1, $expr3, 'different class not deduplicated');
}

done_testing();
