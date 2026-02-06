# ABOUTME: Tests semantic actions for building IR from BNF meta-grammar parse results
# ABOUTME: Verifies each of the 10 semantic action functions builds correct IR nodes
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::Actions;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory for clean test environment
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Test 1: Identifier action creates Constant node with identifier value
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => 'Element',
        children => [],
        position => 0,
        rule     => 'Identifier',
    );

    my $result = Chalk::Bootstrap::Actions::action_Identifier($ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'Identifier creates Constant');
    is($result->const_type(), 'string', 'Identifier constant is string type');
    is($result->value(), 'Element', 'Identifier value is preserved');
}

# Test 2: InlineRegex action creates Constant node with regex value
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => '/[A-Z]+/',
        children => [],
        position => 0,
        rule     => 'InlineRegex',
    );

    my $result = Chalk::Bootstrap::Actions::action_InlineRegex($ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'InlineRegex creates Constant');
    is($result->const_type(), 'string', 'InlineRegex constant is string type');
    is($result->value(), '/[A-Z]+/', 'InlineRegex value is preserved');
}

# Test 3: Quantifier action returns quantifier string
{
    my $ctx = Chalk::Bootstrap::Context->new(
        focus    => '*',
        children => [],
        position => 0,
        rule     => 'Quantifier',
    );

    my $result = Chalk::Bootstrap::Actions::action_Quantifier($ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::Constant', 'Quantifier creates Constant');
    is($result->const_type(), 'string', 'Quantifier constant is string type');
    is($result->value(), '*', 'Quantifier value is preserved');
}

# Test 4: Atom action with Identifier creates reference symbol
{
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'Element');
    my $name_ctx = Chalk::Bootstrap::Context->new(
        focus    => $name_const,
        children => [],
        position => 0,
        rule     => 'Identifier',
    );

    # Atom ::= Identifier
    my $atom_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$name_ctx],
        position => 0,
        rule     => 'Atom',
    );

    my $result = Chalk::Bootstrap::Actions::action_Atom($atom_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::MakeSymbol', 'Atom creates MakeSymbol');
    is($result->inputs()->[0]->value(), 'reference', 'Atom type is reference');
    is($result->inputs()->[1]->value(), 'Element', 'Atom value from Identifier');
}

# Test 5: Atom action with InlineRegex creates terminal symbol
{
    my $regex_const = $factory->make('Constant', const_type => 'string', value => '/[A-Z]+/');
    my $regex_ctx = Chalk::Bootstrap::Context->new(
        focus    => $regex_const,
        children => [],
        position => 0,
        rule     => 'InlineRegex',
    );

    # Atom ::= InlineRegex
    my $atom_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$regex_ctx],
        position => 0,
        rule     => 'Atom',
    );

    my $result = Chalk::Bootstrap::Actions::action_Atom($atom_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::MakeSymbol', 'Atom creates MakeSymbol');
    is($result->inputs()->[0]->value(), 'terminal', 'Atom type is terminal');
    is($result->inputs()->[1]->value(), '/[A-Z]+/', 'Atom value from InlineRegex');
}

# Test 6: Element action with Atom only (no quantifier)
{
    my $type_const = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'Atom');
    my $quant_const = $factory->make('Constant', const_type => 'string', value => undef);

    my $symbol = $factory->make('MakeSymbol',
        type => $type_const,
        value => $name_const,
        quantifier => $quant_const,
    );

    my $symbol_ctx = Chalk::Bootstrap::Context->new(
        focus    => $symbol,
        children => [],
        position => 0,
        rule     => 'Atom',
    );

    # Element ::= Atom (no quantifier)
    my $elem_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$symbol_ctx],
        position => 0,
        rule     => 'Element',
    );

    my $result = Chalk::Bootstrap::Actions::action_Element($elem_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::MakeSymbol', 'Element returns symbol');
    is($result->inputs()->[2]->value(), undef, 'Element has no quantifier');
}

# Test 7: Element action with Atom and Quantifier
{
    my $type_const = $factory->make('Constant', const_type => 'enum', value => 'reference');
    my $name_const = $factory->make('Constant', const_type => 'string', value => 'Rule');
    my $quant_const = $factory->make('Constant', const_type => 'string', value => undef);

    my $symbol = $factory->make('MakeSymbol',
        type => $type_const,
        value => $name_const,
        quantifier => $quant_const,
    );

    my $symbol_ctx = Chalk::Bootstrap::Context->new(
        focus    => $symbol,
        children => [],
        position => 0,
        rule     => 'Atom',
    );

    my $quant_val = $factory->make('Constant', const_type => 'string', value => '+');
    my $quant_ctx = Chalk::Bootstrap::Context->new(
        focus    => $quant_val,
        children => [],
        position => 5,
        rule     => 'Quantifier',
    );

    # Element ::= Atom Quantifier
    my $elem_ctx = Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => [$symbol_ctx, $quant_ctx],
        position => 5,
        rule     => 'Element',
    );

    my $result = Chalk::Bootstrap::Actions::action_Element($elem_ctx);

    isa_ok($result, 'Chalk::Bootstrap::IR::Node::MakeSymbol', 'Element returns symbol');
    is($result->inputs()->[2]->value(), '+', 'Element has quantifier');
}

done_testing();
