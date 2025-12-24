#!/usr/bin/env perl
# ABOUTME: Tests for XS AST node classes and their emit() methods
# ABOUTME: Verifies that each AST node generates correct XS/C code fragments
use 5.42.0;
use Test::More;
use experimental qw(class);

# Test Node base class
{
    use_ok('Chalk::Target::XS::AST::Node') or BAIL_OUT("Cannot load Node");

    # Node should be abstract - calling emit() should die
    my $node = Chalk::Target::XS::AST::Node->new();
    eval { $node->emit() };
    like($@, qr/not implemented/i, 'Node.pm emit() is abstract');
}

# Test Literal node
{
    use_ok('Chalk::Target::XS::AST::Literal') or BAIL_OUT("Cannot load Literal");

    # Integer literal
    my $int_lit = Chalk::Target::XS::AST::Literal->new(value => 42);
    is($int_lit->emit(), '42', 'Integer literal emits correctly');

    # String literal (should emit with quotes)
    my $str_lit = Chalk::Target::XS::AST::Literal->new(value => 'hello');
    is($str_lit->emit(), '"hello"', 'String literal emits with quotes');

    # Floating point literal
    my $float_lit = Chalk::Target::XS::AST::Literal->new(value => 3.14);
    is($float_lit->emit(), '3.14', 'Float literal emits correctly');
}

# Test VarDecl node
{
    use_ok('Chalk::Target::XS::AST::VarDecl') or BAIL_OUT("Cannot load VarDecl");

    # Simple variable declaration
    my $var_decl = Chalk::Target::XS::AST::VarDecl->new(
        type => 'NV',
        name => 'x'
    );
    is($var_decl->emit(), 'NV x;', 'Variable declaration emits correctly');

    # With initialization
    my $var_init = Chalk::Target::XS::AST::VarDecl->new(
        type => 'IV',
        name => 'count',
        init => Chalk::Target::XS::AST::Literal->new(value => 0)
    );
    is($var_init->emit(), 'IV count = 0;', 'Variable with initializer emits correctly');
}

# Test Return node
{
    use_ok('Chalk::Target::XS::AST::Return') or BAIL_OUT("Cannot load Return");

    # Simple return with variable
    my $ret = Chalk::Target::XS::AST::Return->new(
        expr => 'x'
    );
    is($ret->emit(), 'RETVAL = x;', 'Return statement emits correctly');

    # Return with literal
    my $ret_lit = Chalk::Target::XS::AST::Return->new(
        expr => Chalk::Target::XS::AST::Literal->new(value => 42)
    );
    is($ret_lit->emit(), 'RETVAL = 42;', 'Return with literal emits correctly');
}

# Test Module node
{
    use_ok('Chalk::Target::XS::AST::Module') or BAIL_OUT("Cannot load Module");

    # Module declaration
    my $mod = Chalk::Target::XS::AST::Module->new(
        module => 'Foo::Bar',
        package => 'Foo::Bar'
    );
    my $expected = "MODULE = Foo::Bar  PACKAGE = Foo::Bar\n";
    is($mod->emit(), $expected, 'Module declaration emits correctly');
}

# Test XSUB node
{
    use_ok('Chalk::Target::XS::AST::XSUB') or BAIL_OUT("Cannot load XSUB");

    # Simple XSUB
    my $xsub = Chalk::Target::XS::AST::XSUB->new(
        name => 'add',
        params => ['NV a', 'NV b'],
        body => [
            Chalk::Target::XS::AST::Return->new(expr => 'a + b')
        ]
    );

    my $output = $xsub->emit();
    like($output, qr/NV\s+add/, 'XSUB has return type and name');
    like($output, qr/NV a/, 'XSUB includes first parameter');
    like($output, qr/NV b/, 'XSUB includes second parameter');
    like($output, qr/CODE:/, 'XSUB has CODE section');
    like($output, qr/RETVAL = a \+ b;/, 'XSUB body emits correctly');
    like($output, qr/OUTPUT:/, 'XSUB has OUTPUT section');
    like($output, qr/RETVAL/, 'XSUB outputs RETVAL');
}

done_testing();
