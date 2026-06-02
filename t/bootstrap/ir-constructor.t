# ABOUTME: Tests for typed IR node construction (post-Shim migration) for Perl IR types.
# ABOUTME: Verifies typed Chalk::IR::Node::* constructors work for VarDecl, BinaryExpr, etc.
use 5.42.0;
use utf8;

use Test2::V0;

use lib 'lib';
use Chalk::IR::NodeFactory;

# Reset factory to ensure clean test state

my $factory = Chalk::IR::NodeFactory->new;
my $typed   = Chalk::IR::NodeFactory->new;

# Test 1: VarDecl creation (typed)
{
    my $var_name = $factory->make('Constant',
        const_type => 'string',
        value      => '$x',
    );

    my $init = $factory->make('Constant',
        const_type => 'string',
        value      => '42',
    );

    my $decl = $typed->make('VarDecl',
        inputs       => [$var_name, $init],
        compat_class => 'VarDecl',
    );

    isa_ok($decl, 'Chalk::IR::Node');
    is($decl->class(), 'VarDecl', 'class attribute is VarDecl');
    is($decl->operation(), 'VarDecl', 'operation is VarDecl');

    my $inputs = $decl->inputs();
    is($inputs->[0], $var_name, 'first input is variable name');
    is($inputs->[1], $init,     'second input is initializer');
    is($decl->name(), $var_name, 'name() accessor reads variable name');
    is($decl->init(), $init,     'init() accessor reads initializer');
    is($decl->control_in(), undef, 'control is undef when not in a chain');
}

# Test 2: BinaryExpr creation (+ becomes Add)
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

    my $binop = $typed->make('Add',
        inputs       => [$op, $left, $right],
        left         => $left,
        right        => $right,
        compat_class => 'BinaryExpr',
    );

    isa_ok($binop, 'Chalk::IR::Node');
    is($binop->operation(), 'Add', 'BinaryExpr with + becomes Add operation');
}

# Test 3: BuiltinCall creation (Call with dispatch_kind=builtin)
{
    my $name = $factory->make('Constant',
        const_type => 'string',
        value      => 'push',
    );
    my $args = $factory->make('Constant',
        const_type => 'string',
        value      => 'args',
    );

    my $call = $typed->make('Call',
        dispatch_kind => 'builtin',
        name          => $name->value(),
        inputs        => [$name, $args],
        compat_class  => 'BuiltinCall',
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

    # Create VarDecl
    my $decl = $typed->make('VarDecl',
        inputs       => [undef, $const1, $const2],
        compat_class => 'VarDecl',
    );

    # Create ArrayRef with same single constant
    my $arr = $typed->make('ArrayRef',
        inputs       => [$const1],
        compat_class => 'ArrayRefExpr',
    );

    isnt($decl, $arr, 'different Constructor classes are different nodes');
    isnt(refaddr($decl), refaddr($arr), 'reference addresses differ');
}

# Test 5: VarDecl per-position identity - textually-identical decls are distinct
# VarDecl carries per-position (counter) identity, not content-hash identity:
# two declarations with identical name/init are distinct nodes by design (each
# carries its own control_in decoration). See Chalk::IR::Node::VarDecl.
{
    my $var = $factory->make('Constant',
        const_type => 'string',
        value      => '$y',
    );

    my $init = $factory->make('Constant',
        const_type => 'string',
        value      => 'value',
    );

    my $decl1 = $typed->make('VarDecl',
        inputs       => [$var, $init],
        compat_class => 'VarDecl',
    );

    my $decl2 = $typed->make('VarDecl',
        inputs       => [$var, $init],
        compat_class => 'VarDecl',
    );

    isnt($decl1, $decl2, 'identical VarDecl nodes are distinct (per-position identity)');
    isnt(refaddr($decl1), refaddr($decl2), 'reference addresses differ');
}

# Test 6: Hash consing - operation distinguishes nodes
{
    my $const = $factory->make('Constant',
        const_type => 'string',
        value      => 'same',
    );

    my $arr1 = $typed->make('ArrayRef',
        inputs       => [$const],
        compat_class => 'ArrayRefExpr',
    );

    my $arr2 = $typed->make('ArrayRef',
        inputs       => [$const],
        compat_class => 'ArrayRefExpr',
    );

    my $hash = $typed->make('HashRef',
        inputs       => [$const],
        compat_class => 'HashRefExpr',
    );

    is($arr1, $arr2, 'same class and inputs deduplicated');
    isnt($arr1, $hash, 'different class not deduplicated');
}

done_testing();
