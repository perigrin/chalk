#!/usr/bin/env perl
# ABOUTME: Tests for XS built-in function mapping to Perl C API
# ABOUTME: Verifies that Perl built-ins generate correct C API calls
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

use_ok('Chalk::Target::XS') or BAIL_OUT("Cannot load Chalk::Target::XS");
use_ok('Chalk::IR::Node::Call') or BAIL_OUT("Cannot load Call node");
use_ok('Chalk::IR::Node::Constant') or BAIL_OUT("Cannot load Constant node");

# Helper to create an XS target with minimal graph
sub make_xs_target {
    my $graph = { nodes => {}, start => undef, end => undef };
    return Chalk::Target::XS->new(
        graph => $graph,
        module_name => 'Test::Builtins'
    );
}

# Test that built-in mapping exists
{
    my $xs = make_xs_target();
    ok($xs->can('is_builtin'), 'XS target has is_builtin method');
    ok($xs->can('get_builtin_c_api'), 'XS target has get_builtin_c_api method');
}

# Test array built-ins recognition
{
    my $xs = make_xs_target();

    ok($xs->is_builtin('push'), 'push is recognized as builtin');
    ok($xs->is_builtin('pop'), 'pop is recognized as builtin');
    ok($xs->is_builtin('shift'), 'shift is recognized as builtin');
    ok($xs->is_builtin('unshift'), 'unshift is recognized as builtin');
}

# Test hash built-ins recognition
{
    my $xs = make_xs_target();

    ok($xs->is_builtin('exists'), 'exists is recognized as builtin');
    ok($xs->is_builtin('delete'), 'delete is recognized as builtin');
}

# Test scalar built-ins recognition
{
    my $xs = make_xs_target();

    ok($xs->is_builtin('defined'), 'defined is recognized as builtin');
    ok($xs->is_builtin('length'), 'length is recognized as builtin');
}

# Test C API mapping for array operations
{
    my $xs = make_xs_target();

    is($xs->get_builtin_c_api('push'), 'av_push', 'push maps to av_push');
    is($xs->get_builtin_c_api('pop'), 'av_pop', 'pop maps to av_pop');
    is($xs->get_builtin_c_api('shift'), 'av_shift', 'shift maps to av_shift');
    is($xs->get_builtin_c_api('unshift'), 'av_unshift', 'unshift maps to av_unshift');
}

# Test C API mapping for hash operations
{
    my $xs = make_xs_target();

    is($xs->get_builtin_c_api('exists'), 'hv_exists_ent', 'exists maps to hv_exists_ent');
    is($xs->get_builtin_c_api('delete'), 'hv_delete_ent', 'delete maps to hv_delete_ent');
}

# Test C API mapping for scalar operations
{
    my $xs = make_xs_target();

    is($xs->get_builtin_c_api('defined'), 'SvOK', 'defined maps to SvOK');
    is($xs->get_builtin_c_api('length'), 'sv_len', 'length maps to sv_len');
}

# Test non-builtin returns undef
{
    my $xs = make_xs_target();

    ok(!$xs->is_builtin('my_custom_function'), 'custom function not a builtin');
    is($xs->get_builtin_c_api('my_custom_function'), undef, 'custom function has no C API mapping');
}

# Helper to create a builtin call and test its output
sub test_builtin_call {
    my ($func_name, $expected_c_api, $expected_type) = @_;

    use Chalk::IR::Type::String;
    use Chalk::IR::Type::Integer;

    my $xs = make_xs_target();

    my $callee = Chalk::IR::Node::Constant->new(
        value => $func_name,
        type  => Chalk::IR::Type::String->TOP(),
    );
    my $arg = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->TOP(),
    );
    my $call = Chalk::IR::Node::Call->new(
        callee => $callee,
        args   => [$arg],
    );

    # First, visit the argument to bind it
    $xs->visit($arg);

    # Visit the call
    my $result = $xs->visit($call);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl',
        "visit_Call returns VarDecl for $func_name");

    my $emitted = $result->emit();
    like($emitted, qr/\Q$expected_c_api\E/,
        "$func_name() call emits $expected_c_api");
    like($emitted, qr/^\Q$expected_type\E\s/,
        "$func_name() has return type $expected_type");
}

# Test visit_Call generates correct C API for defined
test_builtin_call('defined', 'SvOK', 'bool');

# Test visit_Call generates correct C API for length
test_builtin_call('length', 'sv_len', 'STRLEN');

# Test visit_Call generates correct C API for pop
test_builtin_call('pop', 'av_pop', 'SV*');

# Test visit_Call generates correct C API for shift
test_builtin_call('shift', 'av_shift', 'SV*');

# Test visit_Call generates correct C API for push
test_builtin_call('push', 'av_push', 'IV');

# Test visit_Call generates correct C API for unshift
test_builtin_call('unshift', 'av_unshift', 'IV');

# Test visit_Call generates correct C API for exists
test_builtin_call('exists', 'hv_exists_ent', 'bool');

# Test visit_Call generates correct C API for delete
test_builtin_call('delete', 'hv_delete_ent', 'SV*');

# Test non-builtin function call
{
    use Chalk::IR::Type::String;
    use Chalk::IR::Type::Integer;

    my $xs = make_xs_target();

    my $callee = Chalk::IR::Node::Constant->new(
        value => 'my_custom_func',
        type  => Chalk::IR::Type::String->TOP(),
    );
    my $arg = Chalk::IR::Node::Constant->new(
        value => 42,
        type  => Chalk::IR::Type::Integer->TOP(),
    );
    my $call = Chalk::IR::Node::Call->new(
        callee => $callee,
        args   => [$arg],
    );

    $xs->visit($arg);
    my $result = $xs->visit($call);

    isa_ok($result, 'Chalk::Target::XS::AST::VarDecl',
        'visit_Call returns VarDecl for custom function');

    my $emitted = $result->emit();
    like($emitted, qr/my_custom_func/,
        'Custom function call uses original function name');
    like($emitted, qr/^IV\s/,
        'Custom function has default return type IV');
}

done_testing();
