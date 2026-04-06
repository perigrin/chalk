# ABOUTME: Tests for parameterized Constructor IR node for Perl IR types
# ABOUTME: Verifies Constructor with class parameter works for VarDecl and other Perl IR types
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory to ensure clean test state
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

my $factory = Chalk::Bootstrap::IR::NodeFactory->instance;

# Test 1: Constructor:VarDecl creation
{
    my $var_name = $factory->make('Constant',
        const_type => 'string',
        value      => '$x',
    );

    my $init = $factory->make('Constant',
        const_type => 'string',
        value      => '42',
    );

    my $decl = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var_name,
        initializer => $init,
    );

    isa_ok($decl, 'Chalk::IR::Node');
    is($decl->class(), 'VarDecl', 'class attribute is VarDecl');
    is($decl->operation(), 'VarDecl', 'operation is VarDecl');

    my $inputs = $decl->inputs();
    is($inputs->[0], $var_name, 'first input is variable name');
    is($inputs->[1], $init,     'second input is initializer');
}

# Test 2: Constructor:BinaryExpr creation
{
    my $op = $factory->make('Constant',
        const_type => 'string',
        value      => '+',
    );

    my $left = $factory->make('Constant',
        const_type => 'string',
        value      => 'a',
    );

    my $right = $factory->make('Constant',
        const_type => 'string',
        value      => 'b',
    );

    my $binop = $factory->make('Constructor',
        class => 'BinaryExpr',
        op    => $op,
        left  => $left,
        right => $right,
    );

    isa_ok($binop, 'Chalk::IR::Node');
    is($binop->operation(), 'Add', 'BinaryExpr with + becomes Add operation');
}

# Test 3: Constructor:BuiltinCall creation
{
    my $name = $factory->make('Constant',
        const_type => 'string',
        value      => 'push',
    );
    my $args = $factory->make('Constant',
        const_type => 'string',
        value      => 'args',
    );

    my $call = $factory->make('Constructor',
        class => 'BuiltinCall',
        name  => $name,
        args  => $args,
    );

    isa_ok($call, 'Chalk::IR::Node');
    is($call->class(), 'BuiltinCall', 'BuiltinCall compat_class preserved');
}

# Test 4: Hash consing - different classes not deduplicated
{
    my $const1 = $factory->make('Constant',
        const_type => 'string',
        value      => 'shared',
    );

    my $const2 = $factory->make('Constant',
        const_type => 'string',
        value      => 'other',
    );

    # Create Constructor:VarDecl
    my $decl = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $const1,
        initializer => $const2,
    );

    # Create Constructor:ArrayRefExpr with same single constant
    my $arr = $factory->make('Constructor',
        class     => 'ArrayRefExpr',
        elements  => $const1,
    );

    isnt($decl, $arr, 'different Constructor classes are different nodes');
    isnt(refaddr($decl), refaddr($arr), 'reference addresses differ');
}

# Test 5: Hash consing - same class and inputs deduplicated
{
    my $var = $factory->make('Constant',
        const_type => 'string',
        value      => '$y',
    );

    my $init = $factory->make('Constant',
        const_type => 'string',
        value      => 'value',
    );

    my $decl1 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var,
        initializer => $init,
    );

    my $decl2 = $factory->make('Constructor',
        class       => 'VarDecl',
        variable    => $var,
        initializer => $init,
    );

    is($decl1, $decl2, 'identical Constructor:VarDecl nodes deduplicated');
    is(refaddr($decl1), refaddr($decl2), 'reference addresses match');
}

# Test 6: Hash consing - class attribute distinguishes nodes
{
    my $const = $factory->make('Constant',
        const_type => 'string',
        value      => 'same',
    );

    my $arr1 = $factory->make('Constructor',
        class    => 'ArrayRefExpr',
        elements => $const,
    );

    my $arr2 = $factory->make('Constructor',
        class    => 'ArrayRefExpr',
        elements => $const,
    );

    my $hash = $factory->make('Constructor',
        class  => 'HashRefExpr',
        pairs  => $const,
    );

    is($arr1, $arr2, 'same class and inputs deduplicated');
    isnt($arr1, $hash, 'different class not deduplicated');
}

done_testing();
