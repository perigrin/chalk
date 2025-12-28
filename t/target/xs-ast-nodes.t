#!/usr/bin/env perl
# ABOUTME: Tests for XS AST node classes and their emit() methods
# ABOUTME: Verifies that each AST node generates correct XS/C code fragments
use 5.42.0;
use Test::More;
use experimental qw(class);

# Set lib path at compile time using abs_path on $0 for worktree compatibility
BEGIN {
    use Cwd qw(abs_path);
    use File::Spec;
    my $test_file = abs_path($0);
    my ($vol, $dir, $file) = File::Spec->splitpath($test_file);
    my $lib_dir = abs_path(File::Spec->catdir($vol, $dir, '..', '..', 'lib'));
    unshift @INC, $lib_dir;
}

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

    # Integer literal (c_type from IR::Type::Integer -> IV)
    my $int_lit = Chalk::Target::XS::AST::Literal->new(value => 42, c_type => 'IV');
    is($int_lit->emit(), '42', 'Integer literal emits correctly');
    is($int_lit->c_type(), 'IV', 'Integer literal has correct c_type');

    # String literal (c_type from IR::Type::String -> SV*)
    my $str_lit = Chalk::Target::XS::AST::Literal->new(value => 'hello', c_type => 'SV*');
    is($str_lit->emit(), '"hello"', 'String literal emits with quotes');
    is($str_lit->c_type(), 'SV*', 'String literal has correct c_type');

    # Floating point literal (c_type from IR::Type::Float -> NV)
    my $float_lit = Chalk::Target::XS::AST::Literal->new(value => 3.14, c_type => 'NV');
    is($float_lit->emit(), '3.14', 'Float literal emits correctly');
    is($float_lit->c_type(), 'NV', 'Float literal has correct c_type');

    # Boolean literal (c_type from IR::Type::Bool -> bool)
    my $bool_lit = Chalk::Target::XS::AST::Literal->new(value => 1, c_type => 'bool');
    is($bool_lit->emit(), '1', 'Boolean literal emits correctly');
    is($bool_lit->c_type(), 'bool', 'Boolean literal has correct c_type');

    # Edge case: String literal with quotes (verify escaping works)
    my $quoted_str = Chalk::Target::XS::AST::Literal->new(value => 'say "hello"', c_type => 'SV*');
    is($quoted_str->emit(), '"say \"hello\""', 'String literal with quotes escapes correctly');

    # Edge case: String with backslashes
    my $backslash_str = Chalk::Target::XS::AST::Literal->new(value => 'path\\to\\file', c_type => 'SV*');
    is($backslash_str->emit(), '"path\\\\to\\\\file"', 'String literal with backslashes escapes correctly');

    # Edge case: String with newlines
    my $newline_str = Chalk::Target::XS::AST::Literal->new(value => "line1\nline2", c_type => 'SV*');
    is($newline_str->emit(), '"line1\\nline2"', 'String literal with newlines escapes correctly');

    # Edge case: String with tabs
    my $tab_str = Chalk::Target::XS::AST::Literal->new(value => "col1\tcol2", c_type => 'SV*');
    is($tab_str->emit(), '"col1\\tcol2"', 'String literal with tabs escapes correctly');

    # Edge case: String with multiple special characters
    my $complex_str = Chalk::Target::XS::AST::Literal->new(value => "say \"hello\"\npath\\here", c_type => 'SV*');
    is($complex_str->emit(), '"say \\"hello\\"\\npath\\\\here"', 'String with mixed special chars escapes correctly');

    # Edge case: Empty string literal
    my $empty_str = Chalk::Target::XS::AST::Literal->new(value => '', c_type => 'SV*');
    is($empty_str->emit(), '""', 'Empty string literal emits correctly');

    # Edge case: Negative numbers
    my $neg_int = Chalk::Target::XS::AST::Literal->new(value => -42, c_type => 'IV');
    is($neg_int->emit(), '-42', 'Negative integer emits correctly');

    my $neg_float = Chalk::Target::XS::AST::Literal->new(value => -3.14, c_type => 'NV');
    is($neg_float->emit(), '-3.14', 'Negative float emits correctly');
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
        init => Chalk::Target::XS::AST::Literal->new(value => 0, c_type => 'IV')
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
        expr => Chalk::Target::XS::AST::Literal->new(value => 42, c_type => 'IV')
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

    # Edge case: XSUB with no parameters
    my $xsub_no_params = Chalk::Target::XS::AST::XSUB->new(
        name => 'get_constant',
        params => [],
        body => [
            Chalk::Target::XS::AST::Return->new(expr => '42')
        ]
    );

    my $no_params_output = $xsub_no_params->emit();
    like($no_params_output, qr/NV\s+get_constant/, 'XSUB with no params has return type and name');
    like($no_params_output, qr/CODE:/, 'XSUB with no params has CODE section');
    like($no_params_output, qr/RETVAL = 42;/, 'XSUB with no params body emits correctly');
    like($no_params_output, qr/OUTPUT:/, 'XSUB with no params has OUTPUT section');
}

done_testing();
